//----------------------------------------------------------------------------
// Copyright [2014] [Ztachip Technologies Inc]
//
// Author: Vuong Nguyen
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//----------------------------------------------------------------------------

//---
//-- Float addition
//---


module FP32_ADDSUB
   #(parameter
      LATENCY=8
   )
   (
      input reset_in,
      input clock_in,
      input add_sub_in,
      input [31:0] x1_in,
      input [31:0] x2_in,
      output [31:0] y_out
   );


float_addsub float_addsub_inst
(
  .aclk(clock_in),
  .s_axis_a_tvalid(1),
  .s_axis_a_tdata(x1_in),
  .s_axis_b_tvalid(1),
  .s_axis_b_tdata(x2_in),
  .s_axis_operation_tvalid(1),
  .s_axis_operation_tdata(add_sub_in),
  .m_axis_result_tvalid(),
  .m_axis_result_tdata(y_out)
);

endmodule