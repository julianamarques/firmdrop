// SPDX-License-Identifier: GPL-3.0-or-later
#include "app/md5_verify.hpp"
#include "app/samsung_usb.hpp"
#include "core/path_utf8.hpp"
#include "io/source.hpp"
#include "platform/platform_all.hpp"
#include "protocol/odin/group_flasher.hpp"

#include <spdlog/sinks/stdout_color_sinks.h>
#include <spdlog/spdlog.h>
#include <charconv>
#include <atomic>
#include <filesystem>
#include <iostream>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace {
constexpr auto version = "firmdrop-flash/1 brokkr/f7ae23067b4ee6c2e0211a1dee563f4be991cb4d";
std::mutex output_mutex;

void event(const std::string& text) {
  std::lock_guard lock(output_mutex);
  std::cout << "@firmdrop\t" << text << std::endl;
}

struct Arguments {
  std::string operation, target;
  std::uint64_t connection = 0;
  std::vector<std::filesystem::path> inputs;
  bool preserve = false, reboot = true, resume = false;
};

brokkr::core::Result<Arguments> parse(int argc, char** argv) {
  Arguments out;
  if (argc < 2) return brokkr::core::fail("Expected --version, --list, --probe, --verify or --flash.");
  out.operation = argv[1];
  if (out.operation != "--version" && out.operation != "--list" && out.operation != "--probe" &&
      out.operation != "--verify" && out.operation != "--flash")
    return brokkr::core::fail("Unknown operation.");
  for (int i = 2; i < argc; ++i) {
    const std::string flag = argv[i];
    if (flag == "--preserve") { out.preserve = true; continue; }
    if (flag == "--no-reboot") { out.reboot = false; continue; }
    if (flag == "--resume") { out.resume = true; continue; }
    if (flag != "--target" && flag != "--connection" && flag != "--file")
      return brokkr::core::fail("Unknown option: " + flag);
    if (++i >= argc) return brokkr::core::fail("Missing value for " + flag);
    const std::string value = argv[i];
    if (flag == "--target") out.target = value;
    if (flag == "--file") out.inputs.push_back(brokkr::core::path_from_utf8(value));
    if (flag == "--connection") {
      auto [end, error] = std::from_chars(value.data(), value.data() + value.size(), out.connection);
      if (error != std::errc{} || end != value.data() + value.size())
        return brokkr::core::fail("Invalid connection identifier.");
    }
  }
  if ((out.operation == "--flash" || out.operation == "--probe") &&
      (out.target.empty() || out.connection == 0))
    return brokkr::core::fail("An explicit USB target and connection identifier are required.");
  if (out.resume && out.operation != "--flash" && out.operation != "--probe")
    return brokkr::core::fail("--resume is only valid with --probe or --flash.");
  if ((out.operation == "--flash" || out.operation == "--verify") && out.inputs.size() != 4)
    return brokkr::core::fail("Select exactly four packages: BL, AP, CP and CSC/HOME_CSC.");
  return out;
}

brokkr::core::Status check_connection(const Arguments& args) {
  const auto info = brokkr::app::select_odin_target(args.target);
  if (!info || !info->has_connection_id || info->connection_id != args.connection)
    return brokkr::core::fail("Device disconnected, changed or is not in Download Mode. Detect and test it again.");
  return {};
}

brokkr::odin::Ui make_ui() {
  brokkr::odin::Ui ui;
  ui.on_stage = [](const std::string& value) { event("STAGE\t" + value); };
  ui.on_progress = [last = std::make_shared<std::atomic<int>>(-1)](std::uint64_t done, std::uint64_t total, std::uint64_t, std::uint64_t) {
    const int percent = total ? static_cast<int>(100.0 * done / total) : 0;
    if (percent != last->exchange(percent)) {
      event("PROGRESS\t" + std::to_string(done) + "\t" + std::to_string(total));
    }
  };
  ui.on_error = [](const std::string& value) { spdlog::error("{}", value); };
  return ui;
}

brokkr::core::Result<std::vector<brokkr::odin::ImageSpec>> verify(
    const Arguments& args, const brokkr::odin::Ui& ui) {
  event("STAGE\tVerifying packages");
  std::vector<brokkr::io::RandomAccessSourcePtr> sources;
  for (const auto& path : args.inputs) {
    BRK_TRYV(source, brokkr::io::open_file_source(path));
    if (!brokkr::io::TarArchive::is_tar_file(*source))
      return brokkr::core::fail("Not a TAR firmware package: " + source->label());
    sources.push_back(std::move(source));
  }
  BRK_TRYV(jobs, brokkr::app::md5_jobs_from_sources(sources));
  const auto md5_count = std::ranges::count_if(args.inputs, [](const auto& path) { return path.extension() == ".md5"; });
  if (jobs.size() != static_cast<std::size_t>(md5_count))
    return brokkr::core::fail("A .tar.md5 package has a missing or invalid MD5 trailer.");
  BRK_TRY(brokkr::app::md5_verify(jobs, ui));
  BRK_TRYV(specs, brokkr::odin::expand_inputs(sources, {.allow_raw_files = false}));
  std::vector<brokkr::odin::ImageSpec> filtered;
  for (auto& spec : specs) {
    if (brokkr::odin::is_pit_name(spec.basename)) continue;
    if (args.preserve && (spec.basename == "userdata.img" || spec.basename == "userdata.bin"))
      return brokkr::core::fail("A USERDATA image cannot be flashed with Preserve Data selected.");
    filtered.push_back(std::move(spec));
  }
  if (filtered.empty()) return brokkr::core::fail("No flashable images in the selected packages.");
  return filtered;
}

brokkr::core::Status execute(const Arguments& args) {
  if (args.operation == "--version") { std::cout << version << std::endl; return {}; }
  if (args.operation == "--list") {
    for (const auto& d : brokkr::app::enumerate_samsung_targets()) {
      if (!d.has_connection_id) continue;
      event("DEVICE\t" + d.sysname + "\t" + std::to_string(d.connection_id) + "\t" +
            std::to_string(d.product) + "\t" + (brokkr::app::is_odin_product(d.product) ? "download" : "other"));
    }
    return {};
  }

  auto lock = brokkr::platform::SingleInstanceLock::try_acquire("brokkr-engine");
  if (!lock) return brokkr::core::fail("Another flash engine is running. Close Brokkr or OdinMac and try again.");
  auto ui = make_ui();
  if (args.operation == "--verify") { BRK_TRY(verify(args, ui)); return {}; }
  BRK_TRY(check_connection(args));

  if (args.operation == "--probe") {
    brokkr::odin::UsbTarget usb(args.target);
    BRK_TRY(usb.open_and_connect(2000));
    BRK_TRY(check_connection(args));
    brokkr::odin::OdinCommands odin(usb.conn);
    if (!args.resume) BRK_TRY(odin.handshake(2));
    BRK_TRYV(info, odin.get_version(2));
    BRK_TRY(odin.shutdown(brokkr::odin::OdinCommands::ShutdownMode::NoReboot, 2));
    event("PROBE\t" + std::to_string(static_cast<int>(info.protocol())));
    return {};
  }

  BRK_TRYV(specs, verify(args, ui));
  BRK_TRY(check_connection(args));
  brokkr::odin::UsbTarget usb(args.target);
  brokkr::odin::Cfg cfg;
  cfg.reboot_after = args.reboot;
  brokkr::odin::firmdrop_resume_session = args.resume;
  BRK_TRY(usb.open_and_connect(cfg.preflash_timeout_ms));
  BRK_TRY(check_connection(args));
  brokkr::odin::Target device{.id = args.target, .link = &usb.conn};
  std::vector<brokkr::odin::Target*> targets{&device};
  auto shield = brokkr::core::SignalShield::enable([](const char*, int) {
    spdlog::warn("Flash is active. Keep the device connected until the engine finishes.");
  });
  if (!shield) return brokkr::core::fail("Cannot protect the flash session against interrupts.");
  BRK_TRY(brokkr::odin::flash(targets, specs, {}, cfg, ui));
  event("DONE");
  return {};
}
}

int main(int argc, char** argv) {
  auto logger = spdlog::stderr_color_mt("firmdrop");
  logger->set_pattern("%v");
  spdlog::set_default_logger(logger);
  try {
    const auto args = parse(argc, argv);
    if (!args) { spdlog::error("{}", args.error()); return 2; }
    const auto result = execute(*args);
    if (!result) { spdlog::error("{}", result.error()); return 1; }
    return 0;
  } catch (const std::exception& error) {
    spdlog::error("{}", error.what());
    return 1;
  }
}
