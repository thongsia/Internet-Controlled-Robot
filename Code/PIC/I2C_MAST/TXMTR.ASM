;*********************************************************************************************************
;				PutChar Function
;
;	Function to transmit A Byte Of Data
;	Before calling this routine, load the Byte to be transmitted into TxReg
;	Make sure _txmtProgress & _rcvOver bits (in Status Reg) are cleared before
;	calling this routine
;
;  Program Memory :	6 locations (10 locations if PARITY is Used)
;  Cycles	  :	8 (13 if PARITY is Used)
;
;*********************************************************************************************************
PutChar:
	bsf	_txmtEnable			; enable transmission
	bsf	_txmtProgress
	LOAD_BITCOUNT				; Macro to load bit count
	decf	BitCount2,1
  if _DataBits == 7
	bsf	TxReg,7
  endif
;
   if _PARITY_ENABLE
   	movf	TxReg,W
	call	GenParity			; If Parity is used, then Generate Parity Bit
   endif  
;
	call	_TxmtStartBit
	bsf	_rtie				; Enable RTCC Overflow INT
	retfie					; return with _GIE Bit Set
;
;*********************************************************************************************************
;			Internal Subroutine
; entered from Interrupt Service Routine when Start Bit Is detected.
;
;  Program Memory :   30 locations  (38 locations if PARITY is used)
;  Cycles	  :   15 Worst Case
;
;*********************************************************************************************************

_TxmtNextBit:
	bcf	_rp0
	LOAD_RTCC  0,RtccPreLoad, RtccPrescale	; Macro to reload RTCC
;
	movf	BitCount2, F			;done with data xmission?
	btfsc	_z
	goto	_ParityOrStop			;yes, do parity or stop bit
;
	decf	BitCount2, F
	goto	_NextTxmtBit			;no, send another
;
_ParityOrStop:
    if _PARITY_ENABLE
	btfsc	ExtraBitCount,1			;ready for parity bit?
        goto	_SendParity
    endif
	movf	ExtraBitCount,1			;check if sending stop bit
	btfsc	_z
	goto	DoneTxmt
	decf 	ExtraBitCount,1
;
_StopBit:
	bsf	TX				; STOP Bit is High
	goto	RestoreIntStatus
	goto	DoneTxmt
;
_NextTxmtBit:
	bsf	_carry
	rrf	TxReg, F
	btfss	_carry
        bcf	TX
	btfsc	_carry
	bsf	TX
;
	btfss	_txmtEnable
	bsf	_rtie				; disable further interrupts, Transmission Aborted	
;
	goto	RestoreIntStatus
;
  if _PARITY_ENABLE
_SendParity:
	decf 	ExtraBitCount,1			;subtract parity from count
	btfss	_parityBit
	bcf	TX
	btfsc	_parityBit
        bsf	TX
	goto	RestoreIntStatus
  endif

DoneTxmt
	bsf	TX				;STOP Bit is High
	bcf	_rtie				;disable further interrupts
	bcf	_txmtProgress			;indicates end of xmission
	goto	RestoreIntStatus
;
;*********************************************************************************************************
;			Internal Subroutine
; entered from Interrupt Service Routine when Start Bit Is detected.
;
;  Program Memory :	9 locations
;  Cycles	  :	10
;
;*********************************************************************************************************
_TxmtStartBit:
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
	movlw	(_OPTION_INIT1 | RtccPrescale)
	movwf	_option				; Set Option Reg Located In Page 1
	bcf	_rp0				; make sure to select Page 0
	bcf	TX				; Send Start Bit
	movlw	-RtccPreLoad			; Prepare for Timing Interrupt
	movwf	_rtcc
	bcf	_rtif
	return

;*********************************************************************************************************
;				Generate Parity for the Value in WREG
;
;  The parity bit is set in _parityBit (SerialStatus,7)
;  Common Routine For Both Transmission & Reception
;
;  Program Memory :	16 locations
;  Cycles	  :	72
;
;*********************************************************************************************************
  if _PARITY_ENABLE

GenParity:
	movwf	temp2				;save data
	movf	BitCount2,w			;save bitcount
	movwf	temp1  
Parityloop
        rrf	temp2
	btfss	_carry				;put data in carry bit
	goto	NotOne	
	xorlw	00h				;parity calculated by XORing all data bits
	goto	OneDone
NotOne
	xorlw	01h
OneDone
	decfsz	temp1
	goto	Parityloop			;decrement count
	movwf	temp1
; Parity bit is in Bit 0 of temp1
;
    if _ODD_PARITY
	bsf	_parityBit
	btfsc	temp1,0
        bcf	_parityBit
    else
	bcf	_parityBit
	btfsc	temp1,0
        bsf	_parityBit
    endif

	return
  endif
;*********************************************************************************************************
