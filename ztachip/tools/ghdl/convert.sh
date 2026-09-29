#!/usr/bin/env bash

set -e

cd $(dirname "$0")

ZTACHIP_RTL=../../HW/src

GHDL=./ghdl/bin/ghdl

rm -r -f build

rm -f *.v

mkdir -p build

# Import sources
$GHDL -i --std=08 --work=work --workdir=build -Pbuild \
  "$ZTACHIP_RTL"/*.vhd \
  "$ZTACHIP_RTL"/alu/*.vhd \
  "$ZTACHIP_RTL"/dp/*.vhd \
  "$ZTACHIP_RTL"/ialu/*.vhd \
  "$ZTACHIP_RTL"/pcore/*.vhd \
  "$ZTACHIP_RTL"/fpu/*.vhd \
  "$ZTACHIP_RTL"/soc/*.vhd \
  "$ZTACHIP_RTL"/soc/axi/*.vhd \
  "$ZTACHIP_RTL"/soc/peripherals/*.vhd \
  "$ZTACHIP_RTL"/util/*.vhd \
  "$ZTACHIP_RTL"/top/*.vhd

# Top entity
$GHDL -m --std=08 --work=work --workdir=build soc_base 

# Synthesize: generate Verilog output
$GHDL synth --std=08 --work=work --workdir=build -Pbuild --out=verilog soc_base > soc.v
