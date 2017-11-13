		NOLIST

;*********************************************************************************************************
;	Software Implementation Of RS232 Communications Using PIC16CXX
;				Half-Duplex 
;
;  These routines are intended to be used with PIC16C6X/7X family. These 
;  routines can be used with processors in the 16C6X/7X family which do not 
;  have on board Hardware Async Serial Port.
;  MX..
;
;  Description :
;               Half Duplex RS-232 Mode Is implemented in Software.
;               Both Reception & Transmission are Interrupt driven.
;               Only 1 peripheral (RTCC) used for both transmission & 
;		reception.
;               RTCC is used for both timing generation (for bit 
;		transmission & bit polling) and Start Bit Detection in 
;		reception mode.
;               This is explained in more detail in the Interrupt Subroutine.
;               Programmable Baud Rate (speed depnding on Input Clock Freq.),
;		programmable.
;               #of bits, Parity enable/disable, odd/even parity is 
;		implemented.
;		Parity & Framing errors are detected on Reception
;
;                               RS-232 Parameters
;
;The RS-232 Parameters are defined as shown below:
;
;               _ClkIn          :       Input Clock Frequency of the processor
;                                       (NOTE : RC Clock Mode Is Not Suggested due to wide variations)
;               _BaudRate       :       Desired Baud Rate. Any valid value can be used.
;                                       The highest Baud Rate achievable depends on Input Clock Freq.
;                                       300 to 4800 Baud was tested using 4 Mhz Input Clock
;                                       300 to 19200 Baud was tested using 10 Mhz Input Clock
;                                       Higher rates can be obtained using higher Input Clock Frequencies.
;                                       Once the _BaudRate & _ClkIn are specified the program
;                                       automatically selectes all the appropiate timings
;               _DataBits       :       Can specify 1 to 8 Bits.
;               _StopBits       :       Limited to 1 Stop Bit. Must set it to 1.
;               _PARITY_ENABLE  :       Parity Enable Flag. Set it to TRUE or FALSE. If PARITY
;                                       is used, then set it to TRUE, else FALSE. See "_ODD_PARITY" flag
;                                       description below
;               _ODD_PARITY     :       Set it to TRUE or FALSE. If TRUE, then ODD PARITY is used, else
;                                       EVEN Parity Scheme is used.
;                                       This Flag is ignored if _PARITY_ENABLE is set to FALSE.
;                
;
;  Usage :
;               An example is given in the main program on how to Receive & Transmit Data
;               In the example, the processor waits until a command is received. The command is interpreted
;               as the A/D Channel Number of PIC16C71. Upon reception of a command, the desired A/D channel
;               is selected and after A/D conversion, the 8 Bit A/D data is transmitted back to the Host.
;
;                       The RS-232 Control/Status Reg's bits are explained below :
;
;       "SerialStatus"          : RS-232 Status/Control Register
;
;       Bit 0   :       _txmtProgress   (1 if transmission in progress, 0 if transmission is complete)
;                                       After a byte is transmitted by calling "PutChar" function, the
;                                       user's code can poll this bit to check if transmission is complete.
;                                       This bit is reset after the STOP bit has been transmitted
;       Bit 1   :       _txmtEnable     Set this bit to 1 on initialization to enable transmission.
;                                       This bit can be used to Abort a transmission while the transmitter
;                                       is in progress (i.e when _txmtProgress = 1)
;       Bit 2   :       _rcvProgress    Indicates that the receiver is in middle of reception.It is reset when
;                                       a byte is received.
;       Bit 3   :       _rcvOver        This bit indicates the completion of Reception of a Byte. The user's
;                                       code can poll this bit after calling "GetChar" function. Once "GetChar"
;                                       function is called, this bit is 1 and is set to 0 after reception of
;                                       a complete byte (parity bit if enabled & stop bit)
;       Bit 4   :       _ParityErr      A 1 indicates Parity Error on Reception (for both even & odd parity) 
;       Bit 5   :       _FrameErr       A 1 indicates Framing Error On Reception
;
;       Bit 6   :       _unused_        Unimplemented Bit
;
;       Bit 7   :       _parityBit      The 9 th bit of transmission or reception (status of PARITY bit
;                                       if parity is enabled)
;
;       To Transmit A Byte Of Data :
;                       1) Make sure _txmtProgress & _rcvOver bits are cleared
;                       2) Load TxReg with data to be transmitted
;                       3) CALL  PutChar function                   
;
;       To Receive A Byte Of Data :
;                       1) Make sure _txmtProgress & _rcvOver bits are cleared
;                       2) CALL GetChar function
;                       3) The received Byte is in TxReg after _rcvOver bit is cleared
;
;
;
;       Program:          RS232.ASM 
;       Revision Date:   
;	                  May 17,1994 Scott Fink    (Rev 2)
;	                        	Corrected 7 bit and parity operation, corrected stop bit generation, corrected
;                       		receive prescaler settings.  Protected against inadvertant WDT reset.
;                         12-12-95      Compatibility with MPASMWIN 1.30
;
;*********************************************************************************************************

;*****************************************************************************************
;				RS-232 Header File
;   PIC16C6X/7X/8X
;*****************************************************************************************

_ClkOut		equ	(_ClkIn >> 2)		; Instruction Cycle Freq = CLKIN/4 
;

_CyclesPerBit	set	(_ClkOut/_BaudRate)
_tempCompute	set	(_CyclesPerBit >> 8)
;
;*****************************************************************************************
;		Auto Generation Of Prescaler & Rtcc Values
;   Computed during Assembly Time
;*****************************************************************************************

;  At first set Default values for RtccPrescale & RtccPreLoad
;
RtccPrescale	set	0
RtccPreLoad	set	_CyclesPerBit
UsePrescale	set	FALSE

 if (_tempCompute >= 1)
RtccPrescale	set	0
RtccPreLoad	set	(_CyclesPerBit >> 1)

UsePrescale	set	TRUE
 endif

 if (_tempCompute >= 2)
RtccPrescale	set	1
RtccPreLoad	set	(_CyclesPerBit >> 2)
 endif

 if (_tempCompute >= 4)
RtccPrescale	set	2
RtccPreLoad	set	(_CyclesPerBit >> 3)
 endif

 if (_tempCompute >= 8)
RtccPrescale	set	3
RtccPreLoad	set	(_CyclesPerBit >> 4)
 endif


 if (_tempCompute >= 16)
RtccPrescale	set	4
RtccPreLoad	set	(_CyclesPerBit >> 5)
 endif


 if (_tempCompute >= 32)
RtccPrescale	set	5
RtccPreLoad	set	(_CyclesPerBit >> 6)
 endif

 
 if (_tempCompute >= 64)
RtccPrescale	set	6
RtccPreLoad	set	(_CyclesPerBit >> 7)
 endif


 if   (_tempCompute >= 128)
RtccPrescale	set	7
RtccPreLoad	set	(_CyclesPerBit >> 8)
 endif

;
     if( (RtccPrescale == 0) && (RtccPreLoad < 60))
		messg	"Warning : Baud Rate May Be Too High For This Input Clock"
     endif
;
; Compute RTCC & Presclaer Values For 1.5 Times the Baud Rate for Start Bit Detection
;

_SBitCycles	set	(_ClkOut/_BaudRate) + ((_ClkOut/4)/_BaudRate)
_tempCompute	set	(_SBitCycles >> 8)

_BIT1_INIT	set	08
SBitPrescale	set	0
SBitRtccLoad	set	_SBitCycles


 if (_tempCompute >= 1)
SBitPrescale	set	0
SBitRtccLoad	set	(_SBitCycles >> 1)
_BIT1_INIT	set	0
 endif

 if (_tempCompute >= 2)
SBitPrescale	set	1
SBitRtccLoad	set	(_SBitCycles >> 2)
 endif

 if (_tempCompute >= 4)
SBitPrescale	set	2
SBitRtccLoad	set	(_SBitCycles >> 3)
 endif

 if (_tempCompute >= 8)
SBitPrescale	set	3
SBitRtccLoad	set	(_SBitCycles >> 4)
 endif


 if (_tempCompute >= 16)
SBitPrescale	set	4
SBitRtccLoad	set	(_SBitCycles >> 5)
 endif


 if (_tempCompute >= 32)
SBitPrescale	set	5
SBitRtccLoad	set	(_SBitCycles >> 6)
 endif


 if (_tempCompute >= 64)
SBitPrescale	set	6
SBitRtccLoad	set	(_SBitCycles >> 7)
 endif


 if   (_tempCompute >= 128)
SBitPrescale	set	7
SBitRtccLoad	set	(_SBitCycles >> 8)
 endif

;
;*****************************************************************************************
;
#define	_Cycle_Offset1	24			;account for interrupt latency, call time

LOAD_RTCC	MACRO	Mode, K, Prescale

    if(UsePrescale == 0 && Mode == 0)
	movlw	-K + _Cycle_Offset1
    else
	movlw	-K + (_Cycle_Offset1 >> (Prescale+1))  ; Re Load RTCC init value + INT Latency Offset
    endif
	movwf	_rtcc		; Note that Prescaler is cleared when RTCC is written

		ENDM
;*****************************************************************************************

LOAD_BITCOUNT	MACRO

	movlw	_DataBits+1
	movwf	BitCount2
	movlw	1
	movwf	ExtraBitCount	

    if  _PARITY_ENABLE
	movlw	2
	movwf	ExtraBitCount
    endif

		ENDM
;
;**************************************************************************************************
;			Pin Assignements
;**************************************************************************************************
#define RX_MASK 0x10		; RX pin is connected to RA4, ie. bit 4
#define	RX_Pin	_porta,4	; RX Pin : RA4
#define	RX	RxTemp,4

#define	TX	_portb,7	; TX Pin , RB7

#define	_RTS	_portb,5	; RTS Pin, RB5, Output signal
#define	_CTS	_portb,6	; CTS Pin, RB6, Input signal


#define	_txmtProgress	SerialStatus,0
#define	_txmtEnable	SerialStatus,1

#define	_rcvProgress	SerialStatus,2
#define	_rcvOver	SerialStatus,3
#define	_ParityErr	SerialStatus,4
#define	_FrameErr	SerialStatus,5

#define	_parityBit	SerialStatus,7

;***************************************************************************************************

_OPTION_SBIT	set	0x38		; Increment on Ext Clock (falling edge), for START Bit Detect

 if UsePrescale
_OPTION_INIT1	set	0x00		; Prescaler is used depending on Input Clock & Baud Rate
 else
_OPTION_INIT1	set	0x0F
 endif

		CBLOCK	_End_I2C_Ram
			TxReg			; Transmit Data Holding/Shift Reg
			RxReg			; Rcv Data Holding Reg
                        RxTemp
			SerialStatus		; Txmt & Rev Status/Control Reg
			BitCount2
			ExtraBitCount		; Parity & Stop Bit Count
			SaveWReg		; temp hold reg of WREG on INT
                        SaveStatus		; temp hold reg of STATUS Reg on INT
                    	temp1, temp2
		ENDC

;***************************************************************************************************

		LIST
