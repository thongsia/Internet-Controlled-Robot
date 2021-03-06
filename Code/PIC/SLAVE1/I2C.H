;**********************************************************************************************************
;				I2C Bus Header File
;**********************************************************************************************************



;					Register File Variables


		CBLOCK	0x0C
			SlaveAddr		; Slave Addr must be loader into this reg
			SlaveAddrHi		; for 10 bit addressing mode
			DataByte		; load this reg with the data to be transmitted
			BitCount		; The bit number (0:7) transmitted or received
			Bus_Status		; Status Reg of I2C Bus for both TXMT & RCVE
			Bus_Control		; control Register of I2C Bus
			DelayCount
			DataByteCopy		; copy of DataByte for Left Shifts (destructive)

			SubAddr			; sub-address of slave (used in I2C_HIGH.ASM)
                        SrcPtr			; source pointer for data to be transmitted

			tempCount		; a temp variable for scratch RAM
			StoreTemp_1		; a temp variable for scratch RAM, do not disturb contents
			_End_I2C_Ram
                ENDC

;*************************************************************************************
;			I2C Bus Status Reg Bit Definitions
;*************************************************************************************

#define	_Bus_Busy	Bus_Status,0
#define	_Abort		Bus_Status,1
#define	_Txmt_Progress	Bus_Status,2
#define	_Rcv_Progress	Bus_Status,3

#define	_Txmt_Success	Bus_Status,4
#define	_Rcv_Success	Bus_Status,5
#define	_Fatal_Error	Bus_Status,6
#define	_ACK_Error	Bus_Status,7

;*************************************************************************************
;			I2C Bus Contro Register
;*************************************************************************************
#define	_10BitAddr	Bus_Control,0
#define	_Slave_RW	Bus_Control,1
#define	_Last_Byte_Rcv	Bus_Control,2

#define	_SlaveActive	Bus_Control,6
#define	_TIME_OUT_	Bus_Control,7




;**********************************************************************************************************
;				General Purpose Macros
;**********************************************************************************************************

RELEASE_BUS	MACRO
			bsf	_rp0		; select page 1
			bsf	_SDA		; tristate SDA
			bsf	_SCL		; tristate SCL
;			bcf	_Bus_Busy	; Bus Not Busy, TEMP ????, set/clear on Start & Stop
		ENDM

;**********************************************************************************************************
;			A MACRO To Load 8 OR 10 Bit Address To The Address Registers
;
;  SLAVE_ADDRESS is a constant and is loaded into the SlaveAddress Register(s) depending
;  on 8 or 10 bit addressing modes
;**********************************************************************************************************

LOAD_ADDR_10	MACRO	SLAVE_ADDRESS

		bsf	_10BitAddr	; Slave has 10 bit address        
		movlw	(SLAVE_ADDRESS & 0xff)
        	movwf	SlaveAddr		; load low byte of address  
		movlw	(((SLAVE_ADDRESS >> 7) & 0x06) | 0xF0)	   ; 10 bit addr is 11110XX0  
		movwf	SlaveAddr+1	; hi order  address

		ENDM

LOAD_ADDR_8	MACRO	SLAVE_ADDRESS

		bcf	_10BitAddr	; Set for 8 Bit Address Mode
		movlw	(SLAVE_ADDRESS & 0xff)
		movwf	SlaveAddr

                ENDM
