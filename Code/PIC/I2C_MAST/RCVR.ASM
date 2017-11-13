;*****************************************************************************************
;			GetChar Function
;  Receives a Byte Of Data
;		When reception is complete, _rcvOver Bit is cleared
;		The received data is in RxReg
;
;  Program Memory :	15 locations (17 locations if PARITY is used)
;  Cycles	  :	16 (18 if PARITY is USED)
;
;*****************************************************************************************
GetChar:
	bcf	_rp0
	bsf	_rcvOver		; Enable Reception, this bit gets reset on Byte Rcv Complete
	LOAD_BITCOUNT
        clrf	RxReg
	bcf	_FrameErr
        bcf	_ParityErr	     ; Init Parity & Framing Errors
	clrf	_rtcc
	clrwdt
	bsf	_rp0
	movlw	07h
	movwf	_option
	bcf	_rp0
	clrf	_rtcc
	bsf	_rp0
	movlw	0Fh
	movwf	_option
	clrwdt
        movlw	_OPTION_SBIT	     ; Inc On Ext Clk Falling Edge
	movwf	_option		     ; Set Option Reg Located In Page 1
	bcf	_rp0		     ; make sure to select Page 0
	movlw	0xFF
	movwf	_rtcc		     ; A Start Bit will roll over RTCC & Gen INT
	bcf	_rtif
	bsf	_rtie		     ; Enable RTCC Interrupt
	retfie			     ; Enable Global Interrupt
;
;*****************************************************************************************
;			Internal Subroutine
; entered from Interrupt Service Routine when Start Bit Is detected.
;
;  Program Memory :	14 locations
;  Cycles	  :	12 (worst case)
;
;*****************************************************************************************
_SBitDetected:
	bcf	_rp0
	btfsc	RX_Pin				; Make sure Start Bit Interrupt is not a Glitch
	goto	_FalseStartBit			; False Start Bit	
	bsf	_rcvProgress
	clrf	_rtcc
	clrwdt
	bsf	_rp0
	movlw	07h
	movwf	_option
	bcf	_rp0
	clrf	_rtcc
	bsf	_rp0
	movlw	0Fh
	movwf	_option
	clrwdt
	movlw	(_BIT1_INIT | SBitPrescale)	; Switch Back to INT Clock
	movwf	_option				; Set Option Reg Located In Page 1
	bcf	_rp0				; make sure to select Page 0
	LOAD_RTCC  1,(SBitRtccLoad), SBitPrescale
	goto	RestoreIntStatus
;
_FalseStartBit:
	movlw	0xFF
        movwf	_rtcc				; reload RTCC with 0xFF for start bit detection
	goto	RestoreIntStatus
;
;*****************************************************************************************
;			Internal Subroutine
; entered from Interrupt Service Routine when Start Bit Is detected.
;
;  Program Memory :	28 locations ( 43 locations with PARITY enabled)
;  Cycles	  :     24 Worst Case 
;
;*****************************************************************************************
_RcvNextBit:
	clrwdt
	bsf	_rp0
	movlw	07h
	movwf	_option
	bcf	_rp0
	clrf	_rtcc
	clrwdt
	bsf	_rp0
	movlw	07h
	movwf	_option
	bcf	_rp0
	clrf	_rtcc
	bsf	_rp0
	movlw	0Fh
	movwf	_option
	clrwdt
	movlw	(_OPTION_INIT1 | RtccPrescale)	; Switch Back to INT Clock
	movwf	_option				; Set Option Reg Located In Page 1
;
	bcf	_rp0
	movf	_porta,w	; read RX pin immediately into WREG
	movwf	RxTemp
	LOAD_RTCC  0,RtccPreLoad, RtccPrescale	; Macro to reload RTCC
	movf	_porta,w
	xorwf	RxTemp,w
	andlw	RX_MASK		; mask for only RX PIN (RA4)
	btfsc	_z
	goto	_PinSampled	; both samples are same state
_SampleAgain:
	movf	_porta,w
	movwf	RxTemp		; 2 out of 3 majority sampling done
_PinSampled:
	movf	BitCount2,1
	btfsc	_z
	goto	_RcvP_Or_S
;
	decfsz	BitCount2, F
	goto	_NextRcvBit
;
_RcvP_Or_S:
   if _PARITY_ENABLE
	decfsz	ExtraBitCount
        goto	_RcvParity
   endif
;
_RcvStopBit:
	btfss	RX
	bsf	_FrameErr		; may be framing Error or Glitch        
	bcf	_rtie			; disable further interrupts
	bcf	_rcvProgress
	bcf	_rcvOver		; Byte Received, Can RCV/TXMT an other Byte
  if _PARITY_ENABLE
	movf	RxReg,w
	call	GenParity		; Generate Parity, for Parity check
	movlw	0
	btfsc	_parityBit
	movlw	0x10			; to mask off Received Parity Bit in _ParityErr
	xorwf	SerialStatus 		; _ParityErr bit is set accordingly
  endif
  if _DataBits == 7
	rrf	RxReg,1
	bcf	RxReg,7
  endif
	goto	RestoreIntStatus
;
_NextRcvBit:
	bcf	_carry
	btfsc	RX			; prepare bit for shift
	bsf	_carry	
	rrf	RxReg, F		; shift in received data	
	goto	RestoreIntStatus
;
  if _PARITY_ENABLE
_RcvParity:
	bcf	_ParityErr   		; Temporarily store PARITY Bit in _ParityErr 
	btfsc	RX			; Sample again to avoid any glitches
	bsf	_ParityErr
	goto	RestoreIntStatus
  endif
;
;*****************************************************************************************
