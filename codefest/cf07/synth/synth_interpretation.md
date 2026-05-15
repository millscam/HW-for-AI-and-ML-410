# CF07 Synthesis Interpretation — `synth_top`

Source run: `openlane/runs/RUN_2026-05-15_06-48-24` (Sky130 HD, OpenLane 2.3.10, Option A: project compute core).

## (a) Clock period and worst-case slack


I had the clock period set to 20ns this was set in my config.json. After looking at my percorner table and metrics.csv the "Overall" row has a worst case slack of +8.6973, this shows that there is about 11.3ns of combinational delay and that my clock speed can be potentially increased to 12ish ns while still meeting the worst case mark.


## (b) Critical path

my critical path was from corner `max_ss_100C_1v60`, `sta/50-openroad-stapostpnr__max_ss_100C_1v60__checks.rpt` with the startpoint being the ijnput port g_in[3] input port (green-channel byte) and the endpoint being the flip-flop _1098_ (part of the s1_g150 multiply result register). this DID still meet the slack of 8.6973ns. the dominant cell types were AND/OR/AOI/XOR2 cells (`clkbuf_1`, `buf_2`, `nand2_1`, `mux2_1`, `xnor2_1`, `and3_1`, `or2_1`, `or4_1`, `a31oi_1`, `or3_1`, `or3b_2`, `a21oi_1`, `o21ai_1`, `and3_1`, `dfxtp_1`) 

## (c) Total cell area and top contributors

the post-techmap area is 6308.55 um^2 and 596 but my post PNR stdcell area was 5860.62 um^2 with 884 stdcell instances. this space is mostly occupied by D flip-flops, NAND2 and AND 2 gates found in (sky130_fd_sc_hd__dfxtp_2,sky130_fd_sc_hd__nand2_2, sky130_fd_sc_hd__and2_2)

## (d) Failed constraints, hold violations, warnings

I had 1 DRV violation with my max fanout where my driver is loading 2 inputs per corner, this didnt block the signoff but is something to consider. I also got a notice that my IR drop was of 0.03 percent but it was marked as negligable from my LLM interpretation. other warnings I got were over using default settings. 

