-- Testbench for the Polyphase_SSB module
--
-- Original authors Diego Riste and Colm Ryan
-- Copyright 2015, Raytheon BBN Technologies

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity PolyphaseSSB_tb is
end;

architecture bench of PolyphaseSSB_tb is

signal clk, clk_oserdes: std_logic := '0';
signal reset: std_logic := '0';

constant CLK_PERIOD         : time := 4ns;
constant CLK_OSERDES_PERIOD : time := 2ns;
constant IN_DATA_WIDTH      : natural := 14;
constant OUT_DATA_WIDTH     : natural := 16;

signal wfm_in_re   : std_logic_vector(4*IN_DATA_WIDTH-1 downto 0) := (others => '0');
signal wfm_in_im   : std_logic_vector(4*IN_DATA_WIDTH-1 downto 0) := (others => '0');
signal phinc       : std_logic_vector(23 downto 0) := (others => '0');
signal phoff       : std_logic_vector(23 downto 0) := (others => '0');
signal wfm_out_re  : std_logic_vector(4*OUT_DATA_WIDTH-1 downto 0);
signal wfm_out_im  : std_logic_vector(4*OUT_DATA_WIDTH-1 downto 0);
signal wfm_out_vld : std_logic := '0';

signal wfm_check_re, wfm_check_im : std_logic_vector(15 downto 0) := (others => '0');

signal wfm_oserdes_re, wfm_oserdes_im : std_logic_vector(15 downto 0);

signal temp_realA, temp_realB, tempf_realA, tempf_realB : real;

--define different stages for testbench, corresponding to different SSB parameters
type TESTBENCH_STATE_t	is (RESETTING, BASEBAND_RAMP_RE, BASEBAND_PH_SHIFT, SSB_ON, SSB_PH_SHIFT, DONE);
signal testbench_state : TESTBENCH_STATE_t;

signal stop_the_clocks : boolean := false;

begin

uut: entity work.PolyphaseSSB
	generic map (
		IN_DATA_WIDTH  => IN_DATA_WIDTH,
		OUT_DATA_WIDTH => OUT_DATA_WIDTH
	)
	port map (
		clk           => clk,
		rst           => reset,
		phase_increment => phinc,
		phase_offset    => phoff,
		waveform_in_re  => wfm_in_re,
		waveform_in_im  => wfm_in_im,
		waveform_out_re => wfm_out_re,
		waveform_out_im => wfm_out_im,
		out_vld         => wfm_out_vld
	 );

oserdes_re: entity work.FakeOSERDES
	generic map (
		SAMPLE_WIDTH => OUT_DATA_WIDTH,
		CLK_PERIOD => CLK_OSERDES_PERIOD
	)
	port map (
		clk_in   => clk_oserdes,
		reset    => reset,
		data_in  => wfm_out_re,
		data_out => wfm_oserdes_re
	);

oserdes_im: entity work.FakeOSERDES
generic map (
	SAMPLE_WIDTH => OUT_DATA_WIDTH,
	CLK_PERIOD => CLK_OSERDES_PERIOD
)
port map (
	clk_in   => clk_oserdes,
	reset    => reset,
	data_in  => wfm_out_im,
	data_out => wfm_oserdes_im
);


clk <= not clk after CLK_PERIOD/2 when not stop_the_clocks;
clk_oserdes <= not clk_oserdes after CLK_OSERDES_PERIOD/2 when not stop_the_clocks;

stimulus: process
begin

	--Resetting
	testbench_state <= RESETTING;
	reset <= '1';
	wait for 100ns;
	reset <= '0';
	wait for 20ns;
	wait until rising_edge(clk);

	--clk in baseband ramp on real axis
	testbench_state <= BASEBAND_RAMP_RE;
	for i in -2048 to 2047 loop
		--ramp from min to max
		wfm_in_re <= std_logic_vector(to_signed(4*i+3, IN_DATA_WIDTH))
									& std_logic_vector(to_signed(4*i+2, IN_DATA_WIDTH))
									& std_logic_vector(to_signed(4*i+1, IN_DATA_WIDTH))
									& std_logic_vector(to_signed(4*i, IN_DATA_WIDTH));
		wait until rising_edge(clk);
	end loop ;

	testbench_state <= BASEBAND_PH_SHIFT;
	--set amp. to ~max
	wfm_in_re <= std_logic_vector(to_signed(8191, IN_DATA_WIDTH))
								& std_logic_vector(to_signed(8191, IN_DATA_WIDTH))
								& std_logic_vector(to_signed(8191, IN_DATA_WIDTH))
								& std_logic_vector(to_signed(8191, IN_DATA_WIDTH));
	--shift phase by pi/2 (2^20, 1/4 circle)
	phoff <= std_logic_vector(to_unsigned(4194304, 24));
	wait for 10000ns;

	testbench_state <= SSB_ON;
	phoff <= (others => '0');
	--turn on SSB mod., 10 MHZ frequency (2^24, 1/10 clk)
	--the default width for DDS phases (16 bit) does not give enough accuracy (phase error accumulates)
	phinc <= std_logic_vector(to_unsigned(1677722, 24));
	wait for 10000ns;

	testbench_state <= SSB_PH_SHIFT;
	--shift phase by pi/2
	phoff <= std_logic_vector(to_unsigned(4194304, 24));
	wait for 10000ns;

	testbench_state <= DONE;
	stop_the_clocks <= true;
	wait;
end process;


check : process
-- generate a (complex) signal to check wfm_out_xx against
variable ind : integer range 0 to 1100 := 0;
begin
	--the while loop repeat until the condition is met for the first time (to sync. with wfm_out_xx).
	wait until testbench_state = BASEBAND_RAMP_RE;
	--wait for multiplier and oserdes delay
	for ct in 0 to 9 loop
		wait until rising_edge(clk_oserdes);
	end loop ;
	for i in -8192 to 8191 loop
		--ramp amplitude
		wfm_check_re <= std_logic_vector(to_signed(4*i, OUT_DATA_WIDTH));
		--Arbitrarly allow 2 differences due to fixed point errors
		assert abs(signed(wfm_check_re) - signed(wfm_oserdes_re)) <= 2 report "SSB output wrong in BASEBAND_RAMP_RE!";
		wait until clk_oserdes'event; --only ok in simulation
	end loop ;

	--shift phase by pi/2
	wfm_check_im <= std_logic_vector(to_signed(32752, OUT_DATA_WIDTH));
	wfm_check_re <= (others => '0');

	wait until testbench_state = SSB_ON;
	--wait until DDS is valid (10 cycles) and multiplier pipeline delay (4 cycles)
	for ct in 0 to 29 loop
		wait until rising_edge(clk_oserdes);
	end loop ;

	while testbench_state /= SSB_PH_SHIFT loop
		ind := ind+1;
		tempf_realA  <= cos(MATH_PI*real(ind)/20.0);
		tempf_realB  <= sin(MATH_PI*real(ind)/20.0);
		wfm_check_re <= std_logic_vector(to_signed(integer(tempf_realA*real(32752)), OUT_DATA_WIDTH));
		wfm_check_im <= std_logic_vector(to_signed(integer(tempf_realB*real(32752)), OUT_DATA_WIDTH));
		--Arbitrarly allow 15 differences due to fixed point errors
		assert abs(signed(wfm_check_re) - signed(wfm_oserdes_re)) <= 15 report "SSB output wrong in SSB_ON!";
		wait until clk_oserdes'event;
	end loop;

	ind := 0;
	--wait until DDS is valid (9 cycles) and multiplier pipeline delay (4 cycles)
	for ct in 0 to 28 loop
		wait until rising_edge(clk_oserdes);
	end loop ;

	while not stop_the_clocks loop
		ind := ind+1;
		tempf_realA  <= cos(MATH_PI*real(ind)/20.0 + MATH_PI/2.0);
		tempf_realB  <= sin(MATH_PI*real(ind)/20.0 + MATH_PI/2.0);
		wfm_check_re <= std_logic_vector(to_signed(integer(tempf_realA*real(32752)), OUT_DATA_WIDTH));
		wfm_check_im <= std_logic_vector(to_signed(integer(tempf_realB*real(32752)), OUT_DATA_WIDTH));
		assert abs(signed(wfm_check_re) - signed(wfm_oserdes_re)) <= 15 report "SSB output wrong in SSB_PH_SHIFT";
		wait until clk_oserdes'event;
	end loop;

end process ;

end;
