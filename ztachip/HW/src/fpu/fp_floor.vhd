------------------------------------------------------------------------------
-- Copyright [2014] [Ztachip Technologies Inc]
--
-- Author: Vuong Nguyen
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
------------------------------------------------------------------------------


library std;
use std.standard.all;
LIBRARY ieee;
USE ieee.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.ztachip_pkg.all;

---------
-- Implement floor function
------------

ENTITY fp_floor IS
    generic
    (
        LATENCY : integer
    );
    port(
        SIGNAL clock_in    : IN STD_LOGIC;
        SIGNAL reset_in    : IN STD_LOGIC;
        SIGNAL input_in    : IN fp32_t;
        SIGNAL output_out  : OUT fp32_t
    );
END fp_floor;

ARCHITECTURE fp_floor_behaviour of fp_floor is

signal output:fp32_t;

subtype mantissa_t is STD_LOGIC_VECTOR(fp32_mantissa_width_c-1 DOWNTO 0);

type mantissa_array_t is array (0 to fp32_mantissa_width_c) of mantissa_t;

signal mantissa_mask : mantissa_array_t := (
            "00000000000000000000000", 
            "10000000000000000000000",
            "11000000000000000000000",
            "11100000000000000000000",
            "11110000000000000000000",
            "11111000000000000000000",
            "11111100000000000000000",
            "11111110000000000000000",
            "11111111000000000000000",
            "11111111100000000000000",
            "11111111110000000000000",
            "11111111111000000000000",
            "11111111111100000000000",
            "11111111111110000000000",
            "11111111111111000000000",
            "11111111111111100000000",
            "11111111111111110000000",
            "11111111111111111000000",
            "11111111111111111100000",
            "11111111111111111110000",
            "11111111111111111111000",
            "11111111111111111111100",
            "11111111111111111111110",
            "11111111111111111111111"
            );

BEGIN

delay_i:delayv
    generic map(
        SIZE=>output'length,
        DEPTH=>LATENCY
    )
    port map(
        clock_in=>clock_in,
        reset_in=>reset_in,
        in_in=>output,
        out_out=>output_out,
        enable_in=>'1'
    );

process(input_in)
    variable exp_v : unsigned(fp32_exp_width_c-1 downto 0);
    variable idx_v : unsigned(fp32_exp_width_c-1 downto 0);
begin
    exp_v := unsigned(input_in(30 downto 23));
    if(exp_v < to_unsigned(127,fp32_exp_width_c)) then
        output <= (others=>'0');
    elsif(exp_v > to_unsigned(150,fp32_exp_width_c)) then
        output <= input_in;
    else
        idx_v := exp_v - to_unsigned(127,fp32_exp_width_c);
        output(31 downto 23) <= input_in(31 downto 23);
        output(22 downto 0) <= input_in(22 downto 0) and mantissa_mask(to_integer(idx_v));
    end if;
end process;


END fp_floor_behaviour;

