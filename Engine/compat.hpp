// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <functional>
#ifndef __cpp_lib_move_only_function
#include <function2/function2.hpp>
namespace std {
template <class Signature> using move_only_function = fu2::unique_function<Signature>;
}
#endif
