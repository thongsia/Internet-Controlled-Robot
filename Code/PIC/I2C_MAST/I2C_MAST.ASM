	Title		"RS232-to-I2C Master module"
	SubTitle        "Rev 0.1	:  May 1997"

;****************************************************************************
;
;			RS232-to-I2C module
;
;			Hong-Siang Teo	20/5/97
;
; This program implements a RS232-to-I2C module, which connects a PC to many
; slave I2C devices through the serial port. I'm having problems with I2C_WR,
; so use I2C_WR_SUB instead. For reads, only I2C_READ currently works, not
; I2C_READ_SUB, so I've used a work-around for this.
;
; Note that the original InitI2CBus routine addresses _portb explicitly. It 
; had been changed to _porta.
;
; Also, clock stretching on the I2C bus is disabled, because it competes with
; the RS232 routines for the use of RTCC. This should be ok, since RTCC is
; only useful if the I2C slave is slow.
;****************************************************************************

;****************************************************************************
;
;			Software Implementation Of I2C Master Mode
;
;	* Master Transmitter & Master Receiver Implemented in software 
;	* Slave Mode implemented in hardware
;
;	*	Refer to Signetics/Philips I2C-Bus Specification
;
;    The software is implemented using PIC16C71 & thus can be ported to all 
;    Enhanced core PIC16CXX products
;
;	RA2 is SDA		(Any I/O Pin May Be used instead)
;	RA3 is SCL		(Any I/O Pin May Be used instead)
;	
;
;       Program:          I2CTEST.ASM 
;       Revision Date:   
;                         12-12-95      Compatibility with MPASMWIN 1.30
;
;****************************************************************************

		Processor	16C84
		Radix	DEC

_ClkIn		equ	4000000	; Input Clock Frequency Of PIC16c84    	
_ClkOut	equ	(_ClkIn >> 2)	; Instruction cycle

		include		"16Cxx.h"
;
; I2C bus parameters
;
#define	_ENABLE_BUS_FREE_TIME	TRUE
#define	_CLOCK_STRETCH_CHECK	FALSE	; conflicts with RS232
#define	_INCLUDE_HIGH_LEVEL_I2C	TRUE

		include		"i2c.h"
;
; RS232 parameters
;
_BaudRate       set     1200            ; Baud Rate (bits per second) is 1200
_DataBits       set     8               ; 8 bit data, can be 1 to 8
_StopBits       set     1               ; 1 Stop Bit, 2 Stop Bits is not implemented
#define _PARITY_ENABLE  FALSE           ; NO Parity
#define _ODD_PARITY     FALSE           ; EVEN Parity, if Parity enabled
#define _USE_RTSCTS     FALSE           ; NO Hardware Handshaking is Used

		include		"rs232.h"
;
; RAM usage
;
		CBLOCK
			Command			; command code
			Address			; target slave address
			Bytes			; bytes to transfer
			Sub			; subaddress temp
			Result			; result of operation.
						; 0 if success, 1 otherwise
		ENDC

#define	_Regs	0x28
		CBLOCK	0x28
                	DataBegin	; Data to be read or written is stored here
			; Note that the maximum RAM location is 0x2F, i.e. the 
			; largest single block transfer is limited to 8 bytes.
                ENDC
;
		ORG	0x00
		goto	Start
;
		ORG	0x04
;******************************************************************************
;                               Interrupt Service Routine
;
; Only RTCC Interrupt Is used. RTCC Inturrupt is used as timing for Serial 
; Port Receive & Transmit. Since RS-232 is implemented only as a Half Duplex 
; System, the RTCC is shared by both Receive & Transmit Modules.
;	Transmission :	RTCC is setup for Internal Clock increments and 
;			interrupt is generated when RTCC overflows. Prescaler 
;			is assigned, depending on The INPUT CLOCK & the desired
;			BAUD RATE.
;	Reception :	When put in receive mode, RTCC is setup for external 
;			clock mode (FALLING EDGE) and preloaded with 0xFF. When
;			a Falling Edge is detected on RTCC Pin, RTCC rolls over
;			and an Interrupt is generated (thus Start Bit Detect).
;			Once the start bit is detected, RTCC is changed to 
;			INTERNAL CLOCK mode and RTCC is preloaded with a 
;			certain value for regular timing interrupts to Poll 
;			RTCC Pin (i.e RX pin). 
;
;******************************************************************************
Interrupt:
	btfss   _rtif
	retfie				; other interrupt, return & enable GIE
;
; Save Status On INT : WREG & STATUS Regs
;
	movwf   SaveWReg
	swapf   _status,w               ; affects no STATUS bits : Only way OUT to save STATUS Reg ?????
	movwf   SaveStatus
;
	btfsc   _txmtProgress
	goto    _TxmtNextBit            ; Txmt Next Bit
	btfsc   _rcvProgress
	goto    _RcvNextBit             ; Receive Next Bit
	goto    _SBitDetected           ; Must be start Bit     
;
RestoreIntStatus:
	swapf   SaveStatus,w
	movwf   _status                 ; restore STATUS Reg
	swapf   SaveWReg, F             ; save WREG
	swapf   SaveWReg,w              ; restore WREG
	bcf     _rtif
	retfie

;*****************************************************************************
;				 Include I2C High Level & Low Level Routines
  if _INCLUDE_HIGH_LEVEL_I2C
		include		"i2c_high.asm"
  endif
;
;*****************************************************************************

;***************************************************************************
;	MY_LOAD_ADDR_8
;
; My load address macro, modified to work with a register file
;***************************************************************************

MY_LOAD_ADDR_8	MACRO	SLAVE_ADDRESS
	bcf	_10BitAddr	; Set for 8 Bit Address Mode
	movf	SLAVE_ADDRESS,w
	movwf	SlaveAddr
	ENDM

;***************************************************************************
;	My_I2C_WR_SUB
;
; modified to work with register parameters
;***************************************************************************

MY_I2C_WR_SUB      MACRO   _BYTES_, _SourcePointer_, _Sub_Address_
	movlw	(_BYTES_ +1)
	movwf   tempCount

	movlw   (_SourcePointer_ - 1)
	movwf   _fsr
	movf    _indf,w
	movwf   StoreTemp_1     ; temporarily store contents of (_SourcePointer_ -1)
	movf	_Sub_Address_,w
	movwf   _indf           ; store temporarily the sub-address at (_SourcePointer_ -1)

	call    _i2c_block_write        ; write _BYTES_+1 block of data

	movf    StoreTemp_1,w
	movwf   (_SourcePointer_ - 1)   ; restore contents of (_SourcePointer_ - 1)
	call    TxmtStopBit     ; Issue a stop bit for slave to end transmission
	ENDM

;***************************************************************************
;	COPY
;
; copies the content from a RAM file to another.
; This process is used often enough, so I'll just code it into a macro :)
;***************************************************************************

COPY	MACRO	source,dest
	movf	source,w
	movwf	dest
	ENDM

;******************************************************************************
;
;			   Main Routine  (RS232-to-I2C)
;
;			SINGLE  MASTER, MULTIPLE SLAVES
;
;******************************************************************************

Start:
	call	InitI2CBus_Master	; initialize I2C Bus
	call	InitSerialPort		; initialize RS232 interface
	bsf	_gie			; enable global interrupts
Main:
	call	Receive		; get i2c command code
	COPY	RxReg,Command
	call	Receive		; gets slave's address ...
	COPY	RxReg,Address
	MY_LOAD_ADDR_8	Address	; ... and load it.

	clrf	Result		; init result code to 0 (assume success)
	movf	Command,w	; jump to proper code
	addwf	_pcl,f		; add offset to pcl, for appropriate goto
SelectCommands:
	goto	my_test_device
	goto	my_wr
	goto	my_wr_sub
	goto	my_wr_sub_swinc
	goto	my_wr_byte_mem
	goto	my_wr_buf_mem
	goto	my_read
	goto	my_read_sub
	goto	my_read_status
	goto	my_wr_sub_wr
	goto	my_wr_sub_rd
	goto	my_wr_com_wr

;***************************************************************************
;	The commands subroutines
;***************************************************************************

my_test_device:
	I2C_TEST_DEVICE
	movlw	1
	btfss	_SlaveActive
	movwf	Result		; indicate error
	goto	Return_Result

my_wr:				; NOT IMPLEMENTED
	goto	Return_Result

my_wr_sub:
	call	Receive
;	COPY	RxReg,Bytes	; currently ignored, only single byte write
	call	Receive
	COPY	RxReg,DataBegin
	call	Receive
	COPY	RxReg,Sub
	MY_I2C_WR_SUB	1,DataBegin,0	; only single byte write
	movlw	1
	btfss	_Txmt_Success	; check if successful
	movwf	Result		; indicate error
	goto	Return_Result

my_wr_sub_swinc:		; NOT IMPLEMENTED
	goto	Return_Result

my_wr_byte_mem:			; NOT IMPLEMENTED
	goto	Return_Result

my_wr_buf_mem:			; NOT IMPLEMENTED
	goto	Return_Result

my_read:			; NOT IMPLEMENTED
	goto	Return_Result

my_read_sub:
	call	Receive
	COPY	RxReg,Bytes
	call	Receive
	COPY	RxReg,Sub
	I2C_READ	8,DataBegin
;*** Must use >2 here. If use 1, hang. WHY??? ****
;*** Also, read_sub doesn't hang, but generate errors. WHY??? *****
	movlw	1
	btfss	_Rcv_Success	; set result code
	movwf	Result
_transfer_bytes:
	movf	Sub,w
	andlw	0x07	; only 8 registers
	addlw	_Regs
	movwf	_fsr
	COPY	_indf,TxReg
	incf	Sub,f
	call	Transmit
	decfsz	Bytes,f
	goto	_transfer_bytes
	goto	Return_Result
	
my_read_status:			; NOT IMPLEMENTED
	goto	Return_Result

my_wr_sub_wr:			; NOT IMPLEMENTED
	goto	Return_Result

my_wr_sub_rd:			; NOT IMPLEMENTED
	goto	Return_Result

my_wr_com_wr:			; NOT IMPLEMENTED
;	goto	Return_Result


Return_Result:			; transmit the result code back to PC
	COPY	Result,TxReg
	call	Transmit
	goto	Main

;******************************************************************************
;	InitSerialPort  
;  
;
; Configure TX Pin as output, make sure TX Pin Comes up in high state on Reset
; Configure, RX_Pin (RTCC pin) as Input, which is used to poll data on reception
;
;  Program Memory :     9 locations
;  Cycles         :     10
;*****************************************************************************				
InitSerialPort:
	clrf    SerialStatus
	bcf     _rp0		; select Page 0 for Port Access
	bsf     TX		; make sure TX Pin is high on powerup, use RB Port Pullup                       
	bsf     _rp0		; Select Page 1 for TrisB access
	bcf     TX		; set TX Pin As Output Pin, by modifying TRIS
  if _USE_RTSCTS
	bcf     _RTS		; RTS is output signal, controlled by PIC16Cxx
	bsf     _CTS		; CTS is Input signal, controlled by the host
  endif
	bsf     RX_Pin		; set RX Pin As Input for reception
	bsf	_portb,3	; light up LED
	return

;***************************************************************************
; 	Receive
;
; Receive a byte from the PC and place it in RxReg. The byte is then echoed 
; back to the PC.
;***************************************************************************

Receive
	call	GetChar		; received byte is in _RxReg
	btfsc	_rcvOver	; _rcvOver gets cleared when a byte is received
	goto	$-1		; other task may be performed here

	swapf	RxReg,w		; swap halves, as a test :)
	movwf	TxReg		; copy byte to _TxReg...
	call	PutChar		; ... and echo back to PC
	btfsc	_txmtProgress	; loop until transmission over
	goto	$-1

	movlw	0x08
	xorwf	_portb,f	; toggles LED
	return

;***************************************************************************
;	Transmit
;
; Transmit a byte from TxReg to the PC. An echo will be expected from the PC
;***************************************************************************

Transmit
	call	PutChar		; transmit a byte to the PC
	btfsc	_txmtProgress	; loop until transmission over
	goto	$-1

	call	GetChar		; receive echo from PC
	btfsc	_rcvOver	; _rcvOver gets cleared when a byte is received
	goto	$-1		; other task may be performed here

	movlw	0x08
	xorwf	_portb,f	; toggles LED
	return
;
;******************************************************************************

	include "txmtr.asm" 	; The Transmit routines
	include "rcvr.asm"	; The Receiver Routines

;******************************************************************************
	END

