library IEEE;
use IEEE.Std_logic_1164.all;
use IEEE.Numeric_Std.all;

entity Polyphase_SSB is
	port (
		clock : in std_logic;
		reset : in std_logic;
		waveform_in_re : in std_logic_vector(63 downto 0);
		waveform_in_im : in std_logic_vector(63 downto 0);
  	phinc : in std_logic_vector(23 downto 0); --unsigned 24-bit integer (portion of circle)
  	phoff : in std_logic_vector(23 downto 0); --unsigned 24-bit integer (portion of circle)
  	waveform_out_re : out std_logic_vector(63 downto 0);
		waveform_out_im : out std_logic_vector(63 downto 0)
	) ;
end entity ; -- Polyphase_SSB
 
architecture arch of Polyphase_SSB is
 
signal DDS_valid : std_logic := '0';
signal DDS_phinc : std_logic_vector(23 downto 0) := (others => '0');
signal DDS_phoff : std_logic_vector(23 downto 0) := (others => '0');

type DDS_sincos_t is array(0 to 3) of std_logic_vector(15 downto 0); 
type DDS_phoff_t is array(0 to 3) of std_logic_vector(23 downto 0);
type data_out_t is array(0 to 3) of std_logic_vector(15 downto 0);

signal DDS_cos_array, DDS_sin_array : DDS_sincos_t := (others => (others => '0'));
signal DDS_phoff_array : DDS_phoff_t := (others => (others => '0'));

signal data_out_re, data_out_im : data_out_t := (others => (others => '0'));

begin
	
		waveform_out_re <= data_out_re(3) & data_out_re(2) & data_out_re(1) & data_out_re(0);
		waveform_out_im <= data_out_im(3) & data_out_im(2) & data_out_im(1) & data_out_im(0);
 
	ComplexMultipliergen : for ct in 0 to 3 generate
		myComplexMultiplier : entity work.ComplexMultiply
		port map (
			clock => clock,
			reset => reset,
			data_in_A_re => waveform_in_re((ct+1)*16-1 downto ct*16),
			data_in_A_im => waveform_in_im((ct+1)*16-1 downto ct*16),
			data_in_B_re => DDS_cos_array(ct),
			data_in_B_im => DDS_sin_array(ct),
			data_out_re => data_out_re(ct),
			data_out_im => data_out_im(ct)
			);
	end generate ; -- ComplexMultipliergen

	--an instance of DDS for each of the 4 samples 
	DDS_phoff_array(0) <=  phoff; --std_logic_vector(shift_right(signed(phoff),2)); 
	DDS_phoff_array(1) <=  std_logic_vector(signed(phoff) + shift_right(signed(phinc),4)); --std_logic_vector(shift_right(signed(phoff),1)); 
	DDS_phoff_array(2) <=  std_logic_vector(signed(phoff) + shift_right(signed(phinc),3)); --std_logic_vector(shift_right(signed(phoff),1) + shift_right(signed(phoff),2));
	DDS_phoff_array(3) <=  std_logic_vector(signed(phoff) + shift_right(signed(phinc),4) + shift_right(signed(phinc),3)); 
	--increment phase is 4*input increment phase (in fast clock units)
	DDS_phinc <= std_logic_vector(shift_right(signed(phinc),2)); 

	DDSgen : for ct in 0 to 3 generate
		myDDS : entity work.DDS
		port map (
			aclk => clock,
			aresetn => "not"(reset),
			s_axis_phase_tvalid => '1',
			s_axis_phase_tdata => DDS_phoff_array(ct),
			s_axis_config_tvalid => '1',
			s_axis_config_tdata => DDS_phinc,
			m_axis_data_tvalid => DDS_valid,
			m_axis_data_tdata(31 downto 16) => DDS_sin_array(ct), 
			m_axis_data_tdata(15 downto 0) => DDS_cos_array(ct)
		);
	end generate ; -- DDSgen

end architecture ; -- arch 