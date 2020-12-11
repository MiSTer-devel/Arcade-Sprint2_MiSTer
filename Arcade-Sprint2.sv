//============================================================================
//  Sprint2 port to MiSTer
//  Copyright (c) 2019 Alan Steremberg - alanswx
//
//   
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output [11:0] VIDEO_ARX,
	output [11:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler

	// Use framebuffer from DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of 16 bytes.
	`ifdef USE_FB
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
	`endif

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	
	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT
);

assign VGA_F1    = 0;
assign VGA_SCALER= 0;
assign USER_OUT  = '1;
assign LED_USER  = ioctl_download;
assign LED_DISK  = lamp2;
assign LED_POWER = lamp1;

wire [1:0] ar = status[15:14];

assign VIDEO_ARX =  (!ar) ? ( 8'd4) : (ar - 1'd1);
assign VIDEO_ARY =  (!ar) ? ( 8'd3) : 12'd0;



`include "build_id.v"
localparam CONF_STR = {
	"A.SPRINT2;;",
	"H0OEF,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",  
	"-;",
	"O8,Oil Slicks,On,Off;",
	"O9,Cycle tracks on demo,On,Off;",
	"OA,Extended Play,extended,normal;",
	"OBC,Game time,150 Sec,120 Sec,90 Sec,60 Sec;",
	"OD,Test,Off,On;",
	"OG,Color,Off,On;",		
	"-;",
	"R0,Reset;",
	"J1,Gas,GearUp,GearDown,Next Track,Start 1P,Start 2P,Coin;",
	"jn,A,R,L,X,Start,Select,X;",
	"V,v",`BUILD_DATE
};



wire [31:0] status;
wire  [1:0] buttons;
wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [7:0] ioctl_data;

wire        forced_scandoubler;
wire        direct_video;

wire [21:0] gamma_bus;
wire [10:0] ps2_key;

wire [15:0] joystick_0, joystick_1;
wire [15:0] joy0 =  joystick_0;
wire [15:0] joy1 =  joystick_1;


hps_io #(.STRLEN(($size(CONF_STR)>>3) )) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),
	
	.buttons(buttons),
	.status(status),
	.status_menumask(direct_video),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),
	
	.joystick_0(joystick_0),
	.joystick_1(joystick_1)
);





wire m_left	=  joy0[1];
wire m_right	=  joy0[0];
wire m_gas	=  joy0[4];
wire m_gearup	=  joy0[5];
wire m_geardown	=  joy0[6];

wire m_left_2   =  joy1[1];
wire m_right_2  =  joy1[0];
wire m_gas_2 	=  joy1[4];
wire m_gearup_2	=  joy1[5];
wire m_geardown_2	=  joy1[6];
wire m_next_track	=  joy0[7];

wire m_start1 =  joy0[8] | joy1[8];
wire m_start2 =  joy0[9] | joy1[9];
wire m_coin   =  joy0[10] | joy1[10];



/*
-- Configuration DIP switches, these can be brought out to external switches if desired
-- See Sprint 2 manual page 11 for complete information. Active low (0 = On, 1 = Off)
--    1 								Oil slicks			(0 - Oil slicks enabled)
--			2							Cycle tracks      (0/1 - )
--   			3	4					Coins per play		(00 - 1 Coin per player) 
--						5				Extended Play		(0 - Extended Play enabled)
--							6			Not used				(X - Don't care)
--								7	8	Game time			(01 - 120 Seconds)
--SW1 <= "01000101"; -- Config dip switches

Game Time:
0 0 - 150 seconds
0 1 - 120 seconds
1 0 -  90 seconds
1 1 - 60 seconds

*/

wire [7:0] SW1 = {status[8],~status[9],1'b0,1'b0,status[10],1'b1,status[12:11]};

wire [1:0] steer0;
wire [1:0] steer1;

joy2quad steerjoy2quad0
(
	.CLK(CLK_VIDEO_2),
	.clkdiv('d22500),
	
	.right(m_right),
	.left(m_left),
	
	.steer(steer0)
);
joy2quad steerjoy2quad1
(
	.CLK(CLK_VIDEO_2),
	.clkdiv('d22500),
	
	.right(m_right_2),
	.left(m_left_2),
	
	.steer(steer1)
);

wire gear1,gear2,gear3;
wire [2:0] gear;

gearshift gearshift1
(
	.CLK(clk_12),
	.reset(m_start1|m_start2),
	.gearup(m_gearup),
	.geardown(m_geardown),
	
	.gear1(gear1),
	.gear2(gear2),
	.gear3(gear3),
	.gearout(gear)

);
wire gear1_1,gear1_2,gear1_3;
wire [2:0] gearo1;

gearshift gearshift2
(
	.CLK(clk_12),
	.reset(m_start1|m_start2),
	
	.gearup(m_gearup_2),
	.geardown(m_geardown_2),
	
	.gear1(gear1_1),
	.gear2(gear1_2),
	.gear3(gear1_3),
	.gearout(gearo1)

);


wire videowht,videoblk,compositesync,lamp1,lamp2;
wire [2:0] videorgb;

sprint2 sprint2(
	.Clk_50_I(CLK_50M),
	.Reset_n(~(RESET | status[0]  | buttons[1] | ioctl_download)),

	.dn_addr(ioctl_addr[16:0]),
	.dn_data(ioctl_data),
	.dn_wr(ioctl_wr),

	.VideoW_O(videowht),
	.VideoB_O(videoblk),
	.VideoRGB_O(videorgb),

	.Sync_O(compositesync),
	.Audio1_O(audio1),
	.Audio2_O(audio2),
	.Coin1_I(~(m_coin)),
	.Coin2_I(1'b1),
	.Start1_I(~(m_start1)),
	.Start2_I(~(m_start2)),
	.Trak_Sel_I(~m_next_track),
	.Gas1_I(~m_gas),
	.Gas2_I(~m_gas_2),
	.Gear1_1_I(gear1),
	.Gear2_1_I(gear2),
	.Gear3_1_I(gear3),
	.Gear1_2_I(gear1_1),
	.Gear2_2_I(gear1_2),
	.Gear3_2_I(gear1_3),
	.Gear_Shift_1_I(gear),
	.Gear_Shift_2_I(gearo1),

	.Test_I	(~status[13]),
	.Steer_1A_I(steer0[1]),
	.Steer_1B_I(steer0[0]),
	.Steer_2A_I(steer1[1]),
	.Steer_2B_I(steer1[0]),
	.Lamp1_O(lamp1),
	.Lamp2_O(lamp2),
	.hs_O(hs),
	.vs_O(vs),
	.hblank_O(hblank),
	.vblank_O(vblank),
	.clk_12(clk_12),
	.clk_6_O(CLK_VIDEO_2),
	.SW1_I(SW1)
	);
			
wire [6:0] audio1;
wire [6:0] audio2;
wire [1:0] video;
wire [3:0] videor;
///////////////////////////////////////////////////
wire clk_48,clk_12,CLK_VIDEO_2;
wire clk_sys,locked;
reg [7:0] vid_mono;

always @(posedge clk_sys) begin
		casex({videowht,videoblk})
			2'b01: vid_mono<=8'b01110000;
			2'b10: vid_mono<=8'b10000110;
			2'b11: vid_mono<=8'b11111111;
			2'b00: vid_mono<=8'b00000000;
		endcase
end

assign r=status[16] ? {3{videorgb[2]}} : vid_mono[7:5];
assign g=status[16] ? {3{videorgb[1]}} : vid_mono[7:5];
assign b=status[16] ? {3{videorgb[0]}} : vid_mono[7:5];
assign AUDIO_L={audio1,1'b0,8'b00000000};
assign AUDIO_R={audio2,1'b0,8'b00000000};
assign AUDIO_S = 0;

wire hblank, vblank;
wire hs, vs;
wire [2:0] r,g;
wire [2:0] b;

reg ce_pix;
always @(posedge clk_48) begin
        reg [2:0] div;

        div <= div + 1'd1;
        ce_pix <= !div;
end

arcade_video #(320,9) arcade_video
(
        .*,

        .clk_video(clk_48),

        .RGB_in({r,g,b}),
        .HBlank(hblank),
        .VBlank(vblank),
        .HSync(hs),
        .VSync(vs),

        .fx(status[5:3])
);

pll pll (
	.refclk ( CLK_50M   ),
	.rst(0),
	.locked 		( locked    ),        // PLL is running stable
	.outclk_0	( clk_48),        // 48MHz
	.outclk_1	( clk_12	)        // 12 MHz
	 );

assign clk_sys=clk_12;

endmodule
