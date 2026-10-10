// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <functional>
#ifndef __cpp_lib_move_only_function
#include <function2/function2.hpp>
namespace std {
template <class Signature> using move_only_function = fu2::unique_function<Signature>;
}
#endif

namespace brokkr::odin {
// Set when a previous session on this connection ended without a reboot. Like Heimdall
// --resume, the next session then skips the ODIN/LOKE handshake (resume-session.patch).
extern bool firmdrop_resume_session;
}
