# Specify root clocks

# Specify PLL-generated clock(s)
create_generated_clock -source [get_pins { pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk}] \
                       -name VID_CLK -divide_by 2 -duty_cycle 50 [get_nets {vip|output_inst|vid_clk}]


derive_clock_uncertainty

# Decouple different clock groups (to simplify routing)
set_clock_groups -asynchronous \
   -group [get_clocks { pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk VID_CLK}]
