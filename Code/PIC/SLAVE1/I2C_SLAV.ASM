	Title		"I2C Slave Mode Implemetation"
        SubTitle        "Rev 0.1	:  01 Mar 1993"

;***************************************************************************
;
;			I2C Slave Mode Using Software Polling
;
;  Start Bit Is detected by connecting SDA to RB0/INT Pin
;  Other bits, including STOP & Repeated Start Conditions are software 
;  polled. 
;
;    The software is implemented using PIC16C84 & thus can be ported to all
;	Enhanced core PIC16CXX products
;
;	RB1 is SCL		(Any I/O Pin May Be used instead)
;	RB0/INT is SDA		(Must use this pin for START bit detect when 
;				in idle mode)
;
;       Program:		I2C_SLAV.ASM 
;       Revision Date:		13/3/97
;                       
;
;***************************************************************************
;
	Processor	16C84
	Radix		DEC
	EXPAND

_ClkIn	equ		4000000		; 4MHz clock    	
_ClkOut	equ		(_ClkIn >>2)	; instruction cycle

	INCLUDE		"16cXX.h"

#define	_MY_ADDRESS	0xd0		; This slave's address
#define	_SCL	_portb,1
#define	_SDA	_portb,0

; I2C slave device control registers
	CBLOCK	0x0C
		ControlByte
		SlvStatus
		SubAddr
		DataByte
		DataByteCopy
		BitCount
		SaveStatus		; copy Of STATUS Reg 
		SaveWReg		; copy of WREG
		byteCount
		HoldData
		StepCount0	; motor0 step code counter
		StepCount1	; motor1 step code counter
		Temp
	ENDC

; Control Byte definitions
#define	_STOP	ControlByte, 0
#define	_START	ControlByte, 1
#define	_RW	ControlByte, 2
#define	_ACK	ControlByte, 3

; I2C slave device data registers. All are R/W
; currently 8 registers are defined. Can be more or less.
#define	_Regs	0x28
	CBLOCK	_Regs	; occupies last 8 address
		R0
		R1
		R2
		R3
		R4
		R5
		R6
		R7
	ENDC

_OPTION_SET	set	0x96	; interrupt on INT falling edge,
				; timer clock source set to CLKOUT,
				; prescaler assign to timer,
				; 1:128 ratio.

;***************************************************************************
; Starting address of main program and interrupt handler
;***************************************************************************
	ORG	_ResetVector
	goto	Start
;
	ORG	_IntVector
	goto 	Interrupt

;***************************************************************************
;			Interrupt Service Routine
;
; For I2C Slave routines, only Rb0/INT interrupt is used for START bit 
; detect from Idle Mode.
;
;***************************************************************************

Interrupt:
;
; Save Status
;
	movwf	SaveWReg
	swapf	_status,w	; affects no STATUS bits : Only way OUT to save STATUS Reg ?????
	movwf	SaveStatus
;
;  At first check if START Bit Detect (currently only INT pin interrupt is 
;  enabled, if other interrupts are enabled, then check for other interrupts
;
	btfss	_intf
        goto	other_int		; maybe other interrupt
	btfss	_SCL			; Most likely a START Bit, Hold Time of START Bit must be valid from an INT to here
	goto	RestoreStatus		; Not a Valid START Bit
	btfsc	_SDA			; If a valid Falling Edge on SDA when SCL is high, SDA must now be Low
	goto	RestoreStatus		; Not a Valid START Bit
        goto	StartBitDetect		; A Valid Start Bit Is Detected, process & then Branch to "RestoreStatus"
;
other_int:
	btfsc	_rtif		; real-time clock interrupt ?
	goto	Turn_Motors
;
; Restore Status
;
RestoreStatus:
	swapf	SaveStatus,w
	movwf	_status			; restore STATUS Reg
	swapf	SaveWReg, F		; save WREG
	swapf	SaveWReg,w		; restore WREG
;
	bcf	_intf
	retfie
;

;***************************************************************************
;
;	Main Program
;
; I'm using R0 as the user input registers. It specifies the desired steps 
; for the motor. The MSB indicates the direction (0 for clockwise, 1 for 
; anticlockwise), while the lower 7 bits indicate the steps required (
; max 127 steps at a time). As the motor is turned, the value of R0 will be
; decremented.
; Consecutive writes to R0 will overwrite the previous value. Ideally the user
; should read R0, wait for them to reach 0, before proceeding with the next 
; write.
; R1 and R2 are used to keep track of the position of the motor (16 bit).
; Since I'm half-stepping, a single 8 bit register is not enough. The
; extreme positions are this user defined. Once the motor is at these 
; positions, they can only reverse.
; Note that all these registers are readable and writable, so care should be
; taken in accessing them, especially R1 and R2. If these are messed up, the 
; motor will not be in proper positions.
;
; The port assignment for the motors are:
;	ra0-ra3 : R0, motor 0
;***************************************************************************

Start:
	call	Init_I2C_Slave		; Initialize I2C Bus for Slave Mode, wait for START Bit detect
	bsf	_rtie		; enable RTCC interrupt
	call	Init_Regs	; initialize the regs

	bsf	_gie	; Enable Interrupts
Wait:			; user process goes here
	goto	Wait

Init_Regs:
	clrf	R0	; set input register values to 0 
	clrf	StepCount0	; initial table entry for step codes
	movlw	100
	movwf	R1
; set motor pins to output
	bsf	_rp0		; select tri-state registers
	movlw	0x00
	movwf	_trisa		; set whole porta to output
; set initial motor stator voltages
	bcf	_rp0		; select port registers
	movlw	0x09
	movwf	_porta
	return

;***************************************************************************
;	Interrupt routine to turn motor
; 
; This routine turns the motors 1 full step approximate every 0.1 seconds. 
; It is driven by the RTCC. However, even for a 4 Mhz clock-in, the longest 
; time-interval is only 0.065536s (with prescaler at 256). This is enough
; for half-step mode. But at higher clock rate, a local prescaler has to be
; used.
;
; Note that 'clockwise' here means incrementing the StepCount, while 'anti-
; clockwise' means decrementing the StepCount.
;
; Here anti-clockwise extreme is taken as R1==0, while
; clockwise extreme is R1==255.
;***************************************************************************
Turn_Motors:
; do motor 0 first
	movf	R0,f	; check whether R0 is 0, i.e. no action
	btfsc	_z
	goto	Motor_done
;
; Motor 0 needs to be turned. First, we need to update the relevant registers
;
	btfss	R0,7	; test the turn direction
	goto	_clockwise0
; test extreme position for anti-clockwise
	movf	R1,f		; check if R1==0
	btfsc	_z		; z if set if R1==0
	goto	_extreme0
	decf	R1,f		; update motor position
	decf	StepCount0,f	; anti-clockwise
	bcf	R0,7
	decfsz	R0,f		; if R0 becomes 0, don't bother to set bit 7
	bsf	R0,7
	goto	_turn_motor0
_clockwise0:
	incf	R1,w		; check if R1==255
	btfsc	_z		; z is set if w goes to zero
	goto	_extreme0
	incf	R1,f
	decf	R0,f
	incf	StepCount0,f	; clockwise
;
; now we need to output the appropriate byte to porta to turn motor0
;
_turn_motor0:
	movf	StepCount0,w
	call	StepCode
	bcf	_rp0		; make sure accessing _porta
	movwf	_porta
	goto	Motor_done

_extreme0:
	clrf	R0		; don't do anything if in extreme positions

Motor_done:
	bcf	_rtif
	goto	RestoreStatus

StepCode:
	andlw	0x07	; only 8 codes
	addwf	_pcl,f
	retlw	0x01	; OFF-OFF-OFF-ON
	retlw	0x03	; OFF-OFF-ON-ON
	retlw	0x02	; OFF-OFF-ON-OFF
	retlw	0x06	; OFF-ON-ON-OFF
	retlw	0x04	; OFF-ON-OFF-OFF
	retlw	0x0C	; ON-ON-OFF-OFF
	retlw	0x08	; ON-OFF-OFF-OFF
	retlw	0x09	; ON-OFF-OFF-ON

;***************************************************************************
;	I2C routines
;***************************************************************************
Init_I2C_Slave:
	clrf	ControlByte
	bsf	_rp0
	movlw	_OPTION_SET
	movwf	_option
	bsf	_SCL
	bsf	_SDA		; set TRIS of SCL & SDA to inputs, pulled up by external resistors
	bcf	_rp0
	bcf	_SCL		; set SDA & SCL to zero. 
	bcf	_SDA		; From Now on, simply play with tris
	clrf	SubAddr		; Set Sub Address to Zero

	clrf	_intcon
	bsf	_inte		; Enable Falling Edge Interrupt On SDA (connected on RB0/INT pin)
	return
;
;***************************************************************************
;		       In-Line Code For I2C-Slave
;
;  Returns to detect next Start Bit after a STOP Bit Is Detected
;  This implementation is very in-efficient if the Master is constantly 
;  sending a Repeated START Condition
;	
;***************************************************************************

StartBitDetect:
	call	RcvByte		; 1 st byte received in DataByte

	btfsc	_STOP
	goto	i2c_start_wait	; STOP bit Detected, get out of interrupt
	btfsc	_START
	goto	StartBitDetect	; a Repeated START condition
;
; The received byte in DataByte contains a 7 bit address, and a R/W bit in
; the LSB. If address match send ACK bit else NACK
;
	bcf	_RW
	btfsc	DataByte,LSB
	bsf	_RW		; LSB of the 1st byte received contains R/W info
	bcf	DataByte,LSB

	movf	DataByte,w
	xorlw	_MY_ADDRESS	; if match, then Z bit is set
	btfss	_z
	goto	SendNACK	; No Address Match, NACK
;
; Address Match Occured, send ACK
	bsf	_c		; SendAck routine sends ACK if carry set
	call	SendAck
	btfsc	_RW		; what does he want ? Read or write ?
	goto	SendReqData	; read, so send current Data
	goto	RcvReqData	; write, so receive sub-addr & data byte

;*******************************************************************************************************
;
SendNACK:
	bcf	_c		; SendAck routine sends NACK if carry clear
	call	SendAck		
;
i2c_start_wait:
	bsf	_rp0
	bcf	_intf
	bsf	_SCL		; release CLK line, may be held in low by us
	bsf	_SDA		; release SDA
	goto RestoreStatus	; get out from interrupt

;***************************************************************************
;			Receive A Byte Of Data
;***************************************************************************

RcvByte:
	clrf	SlvStatus

	movlw	0x08
	movwf	BitCount

	bcf	_rp0
	btfsc	_SCL		
	goto	$-1		; wait until SCL is low and then Read the Control Byte

	bsf	_rp0
	bsf	_SCL		; release CLK, possibly held low
	bcf	_rp0
RcvNextBit:
	btfss	_SCL
	goto	$-1		; wait until clock is high, for valid data
	btfsc	_SDA
	goto	Rcvd_1
Rcvd_0:
	bcf	_c
	rlf	DataByte,f	; left shift data ( MSB first)
_WaitClkLo1:
	btfss	_SCL		; wait for clock to go low before reading next bit
	goto	next1
	btfss	_SDA		; SDA must still be low when CLK is high...
	goto	_WaitClkLo1
	bsf	_STOP		; ... else may be a STOP

	return

Rcvd_1:
	bsf	_c
	rlf	DataByte,f
_WaitClkLo2:
	btfss	_SCL
	goto	next1         	; CLK went low, process next bit
	btfsc	_SDA		; SDA must still be high when CLK is high... 
	goto	_WaitClkLo2
	bsf	_START		; else may be a Repeated START

	return

next1:
	decfsz	BitCount,f
	goto	RcvNextBit
;
; A complete byte has been received
; Hold Master's Clock Line Low to force a wait state while we process the
; byte.
;
	bsf	_rp0
	bcf	_SCL		; force SCL Low for wait state
	return

;***************************************************************************
;  			Write Operation Requested
;
; Read sub-address and a data byte & acknowledge, if no errors
; Currently only one byte is programmed at a time
; Buffering scheme is unimplemented
;
;***************************************************************************

RcvReqData
;
; Receive a sub-address
;
	call	RcvByte		; read sub-address first
	movf	DataByte,w
	movwf	SubAddr		; store in SubAddr

	btfsc	_STOP
	goto	i2c_start_wait	; STOP bit Detected, wait for another START
	btfsc	_START
	goto	StartBitDetect	; a Repeated START condition
	bsf	_c		; SendAck routine sends ACK if Carry == 1
	call	SendAck		; Sub-Addr Received, Send an ACK
;
; Receive Data Byte
;
	call	RcvByte		; read data byte

	btfsc	_STOP
	goto	i2c_start_wait	; STOP bit Detected, wait for another START
	btfsc	_START
	goto	StartBitDetect	; a Repeated START condition
	bsf	_c		; SendAck routine sends ACK if Carry == 1
	call	SendAck		; Sub-Addr Received, Send an ACK
;
; now write the data byte to the register
; Hong-Siang Teo	13/3/97
	movf	SubAddr,w	; set up pointer first
	andlw	0x07
	addlw	_Regs
	movwf	_fsr
	movf	DataByte,w
	movwf	_indf		; write to current register

	bsf	_rp0
	bsf	_SCL		; release CLK line, may be held by us
	bsf	_SDA		; release SDA
	goto	RestoreStatus	; STOP bit Detected, wait for another START 

;***************************************************************************
;			Read Operation Requested
;
; Send data until NACK By Master
; Current sub-address is stored in SubAddr
;
; Hong-Siang Teo 3/6/97 :
; I have problems getting I2C_READ_SUB to work. Only I2C_READ works. To
; work around this, for the read operation, the slave will always start at
; SubAddr 0. The master should be aware of this. Currently, my master reads
; the whole 8 bytes at one go, then select the appropriate register value
; from there.
;***************************************************************************

SendReqData:
; send out the requested data from the registers
; Hong-Siang Teo	13/3/97
	clrf	SubAddr		; start at SubAddr 0
SendNextByte:
	movf	SubAddr,w
	andlw	0x07		; only 8 registers
	addlw	_Regs
	movwf	_fsr		; set indirect addressing pointer
	movf	_indf,w		; send out current register data
	movwf	DataByte
	incf	SubAddr,f	; next address

	call	TxmtByte

	btfsc	_START		; check for abnormal START
	goto	i2c_start_wait
	call	ReadACK
	btfss	_ACK		; _ACK == 1 if +ve ACK Rcvd

	goto	i2c_start_wait	; NACK Received, a START or STOP condition may occur
	goto	SendNextByte	; continue to send until NACK

;***************************************************************************
; Put a byte on the SDA
;***************************************************************************
TxmtByte:
	movf	DataByte,w
	movwf	DataByteCopy	; make copy of DataByte 
	movlw	0x08
	movwf	BitCount
	clrf	SlvStatus

TxmtNextBit:
	bsf	_rp0
	rlf	DataByteCopy,f	; MSB First
	btfsc	_c
	goto	Txmt_1
Txmt_0
	bcf	_SDA
	nop
	bsf	_SCL		; release clock line, let master pull it high
	bcf	_rp0
	btfss	_SCL
	goto	$-1		; wait until clk goes high
	btfsc	_SCL
	goto	$-1		; wait until clk goes low
	bsf	_rp0
	bcf	_SCL		; clk went low, continue to hold it low 
	goto	Q_TxmtNextBit
Txmt_1
	bsf	_SDA
	nop
	bsf	_SCL		; release clock line, let master pull it high
	bcf	_rp0
	btfss	_SCL
	goto	$-1		; wait until clk goes high
_IsClkLo_1
	btfss	_SDA
	goto	MayBeErr_Txmt	; must never come here, illegal Repeated Start 
	btfsc	_SCL
	goto	_IsClkLo_1	; wait until clk goes low

	bsf	_rp0
	bcf	_SCL		; clk went low, continue to hold it low 

Q_TxmtNextBit
	decfsz	BitCount,f
	goto	TxmtNextBit
	bsf	_SDA		; release SDA for Master's ACK
	return

MayBeErr_Txmt:
	bsf	_START		; illegal Repeated START condition during a byte transfer
	return

;***************************************************************************
;			Send ACK/NACK to Master
;
; Prior to calling this routine, set CARRY bit to 1 for sending +ve ACK & 
; set CARRY = 0, for NACK
;
;***************************************************************************
SendAck:
	bsf	_rp0
	btfsc	_c		; Carry bit == 1 for ACK else NACK
	bcf	_SDA		; pull SDA low to send +ve ACK
	bsf	_SCL		; release CLK line, let master clk it
	bcf	_rp0
	btfss	_SCL
	goto	$-1		; loop until Clk High
	btfsc	_SCL
	goto	$-1		; loop until Clk is Low, ACK bit sent
	bsf  	_rp0
	bcf	_SCL		; HOLD CLK Line LOW
	bsf	_SDA		; ACK over, release SDA line for Master control		
	return

;***************************************************************************
;			Read ACK Sent By Master
;
; If +ve ACK then set _ACK bit in SlaveStatus Reg, else 0
;
;***************************************************************************
ReadACK:
	bsf	_rp0
	bsf	_SCL		; release clock
	bcf	_rp0
	btfss	_SCL
	goto	$-1		; wait until clock is high (9 the bit:ACK)
	bsf	_ACK		; expecting a +ve ACK
	btfsc	_SDA
	bcf	_ACK		; NACK rcvd, stop transmission
	btfsc	_SCL
	goto	$-1		; wait until Clock is low
	bsf   	_rp0
	bcf	_SCL		; force Clock low
	return

;***************************************************************************
;
	END

