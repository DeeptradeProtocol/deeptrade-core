// Copyright (c) Mysten Labs, Inc.
// Copyright (c) Deeptrade
// SPDX-License-Identifier: Apache-2.0

module deeptrade_core::dt_math;

/// scaling setting for float
const FLOAT_SCALING_U128: u128 = 1_000_000_000;

/// Multiply two floating numbers.
/// This function will round down the result.
public(package) fun mul(x: u64, y: u64): u64 {
    let (_, result) = mul_internal(x, y);
    result
}

/// Divide two floating numbers.
/// This function will round down the result.
public(package) fun div(x: u64, y: u64): u64 {
    let (_, result) = div_internal(x, y);
    result
}

/// Multiply x by y and divide by z.
/// This function will round down the result.
public(package) fun mul_div(x: u64, y: u64, z: u64): u64 {
    let (_, result) = mul_div_internal(x, y, z);
    result
}

fun mul_internal(x: u64, y: u64): (u64, u64) {
    let x = (x as u128);
    let y = (y as u128);
    let round = if ((x * y) % FLOAT_SCALING_U128 == 0) 0 else 1;

    (round, ((x * y) / FLOAT_SCALING_U128 as u64))
}

fun div_internal(x: u64, y: u64): (u64, u64) {
    let x = (x as u128);
    let y = (y as u128);
    let round = if ((x * FLOAT_SCALING_U128 % y) == 0) 0 else 1;

    (round, ((x * FLOAT_SCALING_U128) / y as u64))
}

/// Multiplies `x` by `y` and divides by `z`, where all inputs are fixed-point numbers.
///
/// Fixed-point numbers in this module represent real numbers as scaled integers.
/// A real number `A` is stored as an integer `x = A * S`, where `S` is the scaling
/// factor (`FLOAT_SCALING_U128`).
/// For example, with `S = 1_000_000_000`, the real number 1.5 is stored as 1_500_000_000.
///
/// This function computes `(x * y) / z`. The scaling factors cancel out naturally during
/// the operation, so there is no need to manually adjust for scaling:
///
///   (x * y) / z  =  ((A*S) * (B*S)) / (C*S)
///                =  (A * B * S * S) / (C * S)
///                =  (A * B / C) * S
///
/// The result is the correctly scaled representation of `A * B / C`. This method is also
/// highly precise because it performs multiplication before division, minimizing rounding errors.
fun mul_div_internal(x: u64, y: u64, z: u64): (u64, u64) {
    let x = (x as u128);
    let y = (y as u128);
    let z = (z as u128);
    let round = if ((x * y) % z == 0) 0 else 1;

    (round, ((x * y) / z as u64))
}
