  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
 ;;                                                                          ;;
;;                                                                            ;;
;                               RFID Emulator                                 ;
;;                                                                            ;;
 ;;                                                                          ;;
  ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



	#include "p12f683.inc"	
	#include "RFID_Emulator.inc"
	#include "../Common/RFID_Emulator_io.inc"
	#include "../Common/RFID_Emulator_misc.inc"
	#include "../Common/RFID_Emulator_rf.inc"


	__CONFIG       _CP_ON & _CPD_OFF & _WDT_OFF & _BOD_OFF & _PWRTE_ON & _INTRC_OSC_NOCLKOUT & _MCLRE_ON & _IESO_OFF & _FCMEN_OFF


	GLOBAL	RFID_MEMORY, CONFIG_TAG_MODE, CONFIG_MEMORY_SIZE, CONFIG_CLOCKS_PER_BIT, CONFIG_S_COUNTER
	GLOBAL	_nextTag, _writeConfig


	EXTERN	_initIO
	EXTERN	_writeEEPROM, _readEEPROM , _pauseX10uS, _pauseX1mS
	EXTERN  _initRF, _ISRTimer1RF, _txManchester1, _txManchester0, _txBiphase1, _txBiphase0
	EXTERN	PARAM1

	;#define DEBUG





#DEFINE NUM_BIT_MANCHESTER 2			; Señala en que bit manchester nos encontramos (el primero == 0, o el segundo == 1)
#DEFINE BIT_BASE		   3			; Almacenamos aqui el bit en banda base (no demodulado manchester) 
#DEFINE PROCESAR_BIT_BASE  4			; Indicamos que hay un bit en banda base (no demodulado manchester) que procesar
#DEFINE	BIT 5							; Bit demodulado para ser procesado

#DEFINE GRABADO				0



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                                                                          ;;;
;;                                VARIABLES                                   ;;
;;;                                                                          ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	UDATA

		
RFID_MEMORY		RES 	MAX_MEMORY_SIZE 	; Memory map

									; TAG configuration
CONFIG_TAG_MODE RES 	1			; Tag mode
CONFIG_MEMORY_SIZE RES 	1			; Memory size
CONFIG_CLOCKS_PER_BIT RES 1			; Clocks per bit

CONFIG_S_COUNTER RES 	1			; Memory map counter


TMP_COUNTER		RES 	1			; Tmp counters
BYTE_COUNTER	RES 	1
BIT_COUNTER		RES 	1
	
									; Context vars.
W_TEMP			RES 	1
STATUS_TEMP		RES 	1

TX_BYTE			RES 	1			; Byte transmited


TMP				RES		1

FLAGS			RES		1			; Flags byte

FLAGS_DECO		RES		1
PAQUETE_MANCHESTER	RES 1	; Variable donde almacenamos los dos bits banda base que forman un bit manchester
CONTADOR_BITS_PAQUETE RES 1	; LLeva la cuenta de los bits que esperamos recibir para procesar el paquete
	
PAQUETE RES 1

CONTADOR_NIBBLES RES 1


TRASH	UDATA	0xA0

TRASH			RES		.32			; WARNING! We reserve all the GPRs in the BANK1
									; to avoid the linker using them. 
									; This way, we force the linker to alloc all
									; the vars in the BANK0.
									;
									; The "good" way to do this is doing a linker 
									; script.


	

	

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                                                                          ;;;
;;                                  CODE                                      ;;
;;;                                                                          ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


RST_VECTOR		CODE	0x0000

	GOTO      _start


INT_VECTOR		CODE	0X0004

	; Save the actual context
	MOVWF 	W_TEMP			
	SWAPF 	STATUS,W 
	BCF 	STATUS,RP0
	MOVWF 	STATUS_TEMP

	BTFSC	FLAGS, CAPTURE_MODE_BIT
	GOTO	_ISR_CAPTUREMODE
	
	; Check the TMR1 interruption
	BTFSC	PIR1, TMR1IF
	CALL	_ISRTimer1RF
	GOTO	_ISR_exit

_ISR_CAPTUREMODE
	; Check the TMR1 interruption
	BTFSC	PIR1, TMR1IF
	CALL	_ISRTimer1RF_RX

_ISR_exit

	BANKSEL	STATUS_TEMP					; _ISR_TIMER1RF can return in BANK 1

	; Restore the context
	SWAPF 	STATUS_TEMP,W
	MOVWF 	STATUS
	SWAPF 	W_TEMP,F
	SWAPF 	W_TEMP,W

	RETFIE
	


_start
	CLRF	FLAGS
	CLRF	FLAGS_DECO

	;BUTTON1_CALL_IF_PRESSED	_captureMode	; Start to the capture mode if the B1 is pressed
	goto	_captureMode

_playMode

	CALL	_loadConfig				; Load TAG config
	CALL	_initIO					; Init IO
	MOVFW	CONFIG_CLOCKS_PER_BIT	
	CALL	_initRF					; Init RF
	
	
	


_main

	MOVLW	RFID_MEMORY				; INDF points to the beginning of the RFID memory 
	MOVWF	FSR

	MOVFW	CONFIG_MEMORY_SIZE		; Load the number of bytes to transmit
	MOVWF	BYTE_COUNTER


_byteloop
	
	MOVFW	INDF					; Get the first byte to transmit
	MOVWF	TX_BYTE

	MOVLW	.8						
	MOVWF	BIT_COUNTER

_bitloop

	RLF		TX_BYTE,F				; Bit shifting

	BTFSC	STATUS, C				; Check if the bit is 1 or 0
	CALL	_tx1
	BTFSS	STATUS, C
	CALL	_tx0

	DECFSZ	BIT_COUNTER, F			; Check if more bits are waiting to be transmited
	GOTO	_bitloop

	INCF	FSR, F					; Next byte
	
	DECFSZ	BYTE_COUNTER, F			; Are there more bytes?
	GOTO	_byteloop

	goto 	_main


_tx1

	; Check the modulation
	BTFSC	CONFIG_TAG_MODE, TAG_MODE_CODING_BIT
	CALL	_txBiphase1

	BTFSS	CONFIG_TAG_MODE, TAG_MODE_CODING_BIT
	CALL	_txManchester1

	RETURN



_tx0

	; Check the modulation
	BTFSC	CONFIG_TAG_MODE, TAG_MODE_CODING_BIT
	GOTO	_txBiphase0
	
	BTFSS	CONFIG_TAG_MODE, TAG_MODE_CODING_BIT
	GOTO	_txManchester0

	RETURN






;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                                                                          ;;;
;;                                                                            ;;
;    Function:  _loadConfig                                                    ;
;    Desc.:     Load the tag configuration                                     ;
;    Vars:      CONFIG_TAG_MODE, CONFIG_TAG_REPETITION, CONFIG_MEMORY_SIZE,    ;
;               CONFIG_S_COUNTER                                               ;
;                                                                              ;
;    Notes:                                                                    ;
;;                                                                            ;;
;;;                                                                          ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_loadConfig

	MOVLW	EE_S_COUNTER			; Recover the active memory map
	CALL	_readEEPROM	
	MOVWF	CONFIG_S_COUNTER

	CALL	_mapOffset				; Calculate the map offset
	MOVWF	TMP						; Temporaly, store the offset


	MOVLW	EE_S0_TAG_MODE			; Read the tag mode
	ADDWF	TMP, W					
	CALL	_readEEPROM
	MOVWF	CONFIG_TAG_MODE

	MOVLW	EE_S0_MEMORY_SIZE		; Read the memory size
	ADDWF	TMP, W			
	CALL	_readEEPROM
	MOVWF	CONFIG_MEMORY_SIZE

	MOVLW	EE_S0_CLOCKS_PER_BIT	; Read the clocks per bit
	ADDWF	TMP, W					
	CALL	_readEEPROM
	MOVWF	CONFIG_CLOCKS_PER_BIT



	MOVLW	EE_S0_RFID_MEMORY		; Read the memory map
	ADDWF	TMP, W			
	CALL	_loadMemoryMap

	RETURN





;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                                                                          ;;;
;;                                                                            ;;
;    Function:  _loadMemoryMap                                                 ;
;    Desc.:     Load the Memory Map from the EEPROM to the RAM                 ;
;    Params.:   W -> EEPROM ADDRESS                                            ;
;    Vars:      TMP                                                            ;
;                                                                              ;
;;                                                                            ;;
;;;                                                                          ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_loadMemoryMap


	MOVWF	BYTE_COUNTER			; Save the EEPROM ADDRESS (W)

	ADDWF	CONFIG_MEMORY_SIZE, W	; Save in TMP the end of the memory map
	MOVWF	TMP					

	MOVLW	RFID_MEMORY				; INDF points at the beginning of the memory map
	MOVWF	FSR

	

_loadMemoryMap_loop

	MOVFW	BYTE_COUNTER			; Read the EEPROM byte
	CALL	_readEEPROM
	MOVWF	INDF					; Store it in the RAM

	INCF	FSR, F					; Point to the next memory map byte 


	INCF	BYTE_COUNTER, F			; Check if we have copied all the bytes
	MOVFW	TMP
	SUBWF	BYTE_COUNTER, W
	BTFSS	STATUS, Z
	GOTO	_loadMemoryMap_loop

	return



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                                                                          ;;;
;;                                                                            ;;
;    Function:  _writeConfig                                                   ;
;    Desc.:     Write the tag configuration                                    ;
;    Vars:      CONFIG_TAG_MODE, CONFIG_TAG_REPETITION, CONFIG_MEMORY_SIZE,    ;
;               CONFIG_S_COUNTER                                               ;
;                                                                              ;
;    Notes:                                                                    ;
;;                                                                            ;;
;;;                                                                          ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_writeConfig
	
	BCF		INTCON, GIE				; Stop interrupts

	MOVLW	EE_S_COUNTER			; write the active memory map
	MOVWF	PARAM1
	MOVFW	CONFIG_S_COUNTER
	CALL	_writeEEPROM	
	
	MOVFW	CONFIG_S_COUNTER
	CALL	_mapOffset				; Calculate the map offset
	MOVWF	TMP						; Temporaly, store the offset


	MOVLW	EE_S0_TAG_MODE			; Write the tag mode
	ADDWF	TMP, W					
	MOVWF	PARAM1
	MOVFW	CONFIG_TAG_MODE
	CALL	_writeEEPROM
	

	MOVLW	EE_S0_MEMORY_SIZE		; Write the memory size
	ADDWF	TMP, W		
	MOVWF	PARAM1	
	MOVFW	CONFIG_MEMORY_SIZE
	CALL	_writeEEPROM
	

	MOVLW	EE_S0_CLOCKS_PER_BIT	; Write the clocks per bit
	ADDWF	TMP, W
	MOVWF	PARAM1
	MOVFW	CONFIG_CLOCKS_PER_BIT			
	CALL	_writeEEPROM




	MOVLW	EE_S0_RFID_MEMORY		; Write the memory map
	ADDWF	TMP, W			
	CALL	_writeMemoryMap

	BSF		INTCON, GIE				; Stop interrupts

	RETURN



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                                                                          ;;;
;;                                                                            ;;
;    Function:  _writeMemoryMap                                                ;
;    Desc.:     Write the Memory Map from the RAM to the EEPROM                ;
;    Params.:   W -> EEPROM ADDRESS                                            ;
;    Vars:      TMP                                                            ;
;                                                                              ;
;;                                                                            ;;
;;;                                                                          ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_writeMemoryMap


	MOVWF	BYTE_COUNTER			; Save the EEPROM ADDRESS (W)

	ADDWF	CONFIG_MEMORY_SIZE, W	; Save in TMP the end of the memory map
	MOVWF	TMP					

	MOVLW	RFID_MEMORY				; INDF points at the beginning of the memory map
	MOVWF	FSR

	

_writeMemoryMap_loop

	MOVFW	BYTE_COUNTER			; Write the EEPROM address
	MOVWF	PARAM1

	MOVFW	INDF					; Recovers the map byte in RAM

	CALL	_writeEEPROM
	

	INCF	FSR, F					; Point to the next memory map byte 


	INCF	BYTE_COUNTER, F			; Check if we have copied all the bytes
	MOVFW	TMP
	SUBWF	BYTE_COUNTER, W
	BTFSS	STATUS, Z
	GOTO	_writeMemoryMap_loop

	return




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                                                                          ;;;
;;                                                                            ;;
;    Function:  _nextTag / _nextTag_Blinking                                   ;
;    Desc.:     Change the memory map                                          ;
;    Vars:      CONFIG_S_COUNTER, TMP3                                         ;
;                                                                              ;
;;                                                                            ;;
;;;                                                                          ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_nextTag_Blinking

	call	_nextTag

	
	; The number of the map is displayed thanks to a blinking led

	INCF	CONFIG_S_COUNTER, W		; TMP_COUNTER = map number + 1
	MOVWF	TMP_COUNTER

	SUBLW	.6						; W = 6 - map num
	BTFSC	STATUS, C				; 
	GOTO	_nextTag_loop			; map num <= 6
	
	LED2_ON							; map num > 6
	MOVLW	.6
	SUBWF	TMP_COUNTER, F


_nextTag_loop

	; LED ON for 125 mS except if the map number is  divisible by 5 (250 ms)
	LED1_ON								
	MOVLW	.200
	CALL	_pauseX1mS

	LED1_OFF
	MOVLW	.200
	CALL	_pauseX1mS
	
	DECFSZ	TMP_COUNTER, F
	GOTO	_nextTag_loop

	LED2_OFF

	BUTTON1_WAIT_UNTIL_NOT_PRESSED
	MOVLW	.100
	CALL	_pauseX1mS




	RETURN


_nextTag

	INCF	CONFIG_S_COUNTER, F		; Incr. the number of the actual map
	
	; Check if we reached the limit
	MOVLW	NUM_TAGS				; Load the number of tags
	SUBWF	CONFIG_S_COUNTER, W			
	BTFSC	STATUS, Z				; is actual map greater than the limit?
	CLRF	CONFIG_S_COUNTER		; yes -> actual map = 0


	; Write the actual map number in the EEPROM
	MOVLW	EE_S_COUNTER
	MOVWF	PARAM1
	MOVFW	CONFIG_S_COUNTER
	CALL	_writeEEPROM

	call	_loadConfig				; Load the config of the new map


	RETURN


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                                                                          ;;;
;;                                                                            ;;
;    Function:  _mapOffset                                                     ;
;    Desc.:     Return the memory map offset                                   ;
;    Params:    W -> Number of the memory map                                  ;
;    Return:    W -> Offset                                                    ;
;                                                                              ;
;    Notes:     Warning! PCL should not be overflowed with the ADDWF PCL, F    ; 
;;                                                                            ;;
;;;                                                                          ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_mapOffset

	MOVWF	TMP
	MOVLW	HIGH _mapOffset
	MOVWF	PCLATH

	MOVFW	TMP
	ADDWF	PCL, F
	RETLW	EE_S0_MEMORY_SIZE
	RETLW	EE_S1_MEMORY_SIZE
	RETLW	EE_S2_MEMORY_SIZE
	RETLW	EE_S3_MEMORY_SIZE
	RETLW	EE_S4_MEMORY_SIZE
	RETLW	EE_S5_MEMORY_SIZE
	RETLW	EE_S6_MEMORY_SIZE
	RETLW	EE_S7_MEMORY_SIZE
	RETLW	EE_S8_MEMORY_SIZE
	RETLW	EE_S9_MEMORY_SIZE
	RETLW	EE_S10_MEMORY_SIZE
	RETLW	EE_S11_MEMORY_SIZE

	RETURN










_captureMode

	CALL	_loadConfig				; Load TAG config
	CALL	_initIO					; Init IO
	MOVFW	CONFIG_CLOCKS_PER_BIT	
	CALL	_initRF_RX					; Init RF

_mainRX
	call	_stopRX	

	BANKSEL	CMCON0

	BTFSC	CMCON0, COUT			; Esperamos que baje el flanco
	GOTO	$-1
	BTFSS	CMCON0, COUT			; Esperamos que suba el flanco
	GOTO	$-1

	BANKSEL	TMP

	; Pausamos un poco 

	MOVLW 	.20
	MOVWF	TMP	
	
	DECFSZ	TMP, F
	GOTO	$-1

	call	_startRX

	CLRF	FLAGS_DECO
	CLRF	PAQUETE_MANCHESTER
	CLRF	CONTADOR_BITS_PAQUETE
		
	

	movlw	.8
	movwf	CONTADOR_NIBBLES
	
	; Comprobamos si recibimos el par cero-uno ocho veces. Si hay algun error, salimos.
_comprobarCabecera

	BTFSS	FLAGS_DECO, PROCESAR_BIT_BASE
	GOTO	$-1
	BCF		FLAGS_DECO, PROCESAR_BIT_BASE
	BTFSC	FLAGS_DECO, BIT_BASE				; Esperamos un cero
	GOTO	_mainRX						; No es un cero, volvemos a empezar...

	BTFSS	FLAGS_DECO, PROCESAR_BIT_BASE
	GOTO	$-1
	BCF		FLAGS_DECO, PROCESAR_BIT_BASE
	BTFSS	FLAGS_DECO, BIT_BASE				; Esperamos un uno
	GOTO	_mainRX						; No es un uno, volvemos a empezar...

	DECFSZ	CONTADOR_NIBBLES, F
	GOTO	_comprobarCabecera

	LED1_ON

	GOTO	$-1




;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;                                                                          ;;;
;;                                                                            ;;
;    Function:  _initRF_RX                                                     ;
;    Desc.:     Initialize the RF                                              ;
;    Params.:   W -> CARRIER CLOCKS PER BIT                                    ;
;    Vars:      TMP                                                            ;
;                                                                              ;
;    Notes:     The TMR2 interruption is activated.                            ; 
;;                                                                            ;;
;;;                                                                          ;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

_initRF_RX


	MOVWF	TMP					; Backup of the CLOCK_PER_BIT value stored in W

	BSF		FLAGS, CAPTURE_MODE_BIT

	;MOVLW	b'00010100'			; Comparator Output Inverted. CIN- == GP0 ; CIN+ == CVref
	MOVLW	b'00010011'			; Comparator Output Inverted. CIN- == GP0 ; CIN+ == CVref; COUT PIN enabled
	MOVWF	CMCON0

	BANKSEL	TRISIO				; Bank 1

	MOVLW	b'00000010'			; GP1 as analog input. Rest as digital
	MOVWF	ANSEL
	
	;MOVLW	b'10100011'			; Voltage Regulator ON; Low range; 0.625 volts (Vdd=5V)
	MOVLW	b'10100000'			; Voltage Regulator ON; Low range; 0.04 Vdd
	;MOVLW	b'10000000'			; Voltage Regulator ON; HIGH range; 0.750 Vdd
	MOVWF	VRCON
	
	BSF		DEMODULATOR_TRIS	; Demodulator pin as input


	BSF		COIL1_TRIS			; Coil pins as input
	BSF		COIL2_TRIS			

BCF		TRISIO, GP2			; TESTING. COUT salida

	BANKSEL	GPIO				; Bank 0

	BCF		COIL1				; COIL1 connected to GND (if COIL1_TRIS = 0)	


	RETURN


_startRX

	BCF	PIR1, TMR1IF			; Clear the TMR1IF flag

	BANKSEL	PIE1

	CLRF	PIE1				; Activate the Timer1 Interruption
	BSF		PIE1, TMR1IE				

	BANKSEL PIR1

	MOVLW	b'11000000'			; Activate GIE and PEIE
	MOVWF	INTCON
	
	
	MOVLW	0xFF				; Write the Timer1 upper byte
	MOVWF	TMR1H

	; Write the Timer1 lower byte. TMR1L = 0 - CLOCKS_PER_BIT/2
	BCF		STATUS, C					
	RRF		TMP, W						; CLOCKS_PER_BIT / 2 -> W
	ADDLW	-2							; Tuning. 
	CLRF	TMR1L						; TMR1L = 0
	SUBWF	TMR1L, F

	IFDEF	DEBUG
	MOVLW	b'00110001'					; Timer1: internal clock source, synchronous, prescalerx8.
	ELSE
	MOVLW	b'00000111'					; Timer1: external clock source, synchronous, no prescaler.
	ENDIF
	MOVWF	T1CON						; Timer1 config

	RETURN


_stopRX


	BANKSEL	PIE1

	; DeActivate the Timer1 Interruption
	BCF		PIE1, TMR1IE				

	BANKSEL PIR1

	BCF	PIR1, TMR1IF			; Clear the TMR1IF flag	

	MOVLW	b'01000000'			; Activate GIE and PEIE
	MOVWF	INTCON
	
	

	RETURN



_ISRTimer1RF_RX

	BCF		PIR1, TMR1IF			; Cleart the TMR1F flag

	BANKSEL	PIE1					; Bank 1

	BTFSS	PIE1, TMR1IE			; Check for ghost interrupts
	RETURN							; WARNING! Return with the Bank 1 selected

	BANKSEL	TMR1H					; Bank 0	
	



	MOVLW	0xFF				; Write the Timer1 upper byte
	MOVWF	TMR1H

	; Write the Timer1 lower byte. TMR1L = 0 - CLOCKS_PER_BIT/2
	BCF		STATUS, C					
	RRF		CONFIG_CLOCKS_PER_BIT, W		; CLOCKS_PER_BIT / 2 -> W
	ADDLW	-2							; Tuning.
	CLRF	TMR1L						; TMR1L = 0
	SUBWF	TMR1L, F

	
	BSF		FLAGS_DECO, PROCESAR_BIT_BASE		; Avisamos de que hay un bit por procesar


	BANKSEL	CMCON0
	BTFSC	CMCON0, COUT				; Muestreado un 1
	GOTO	_uno
	
_cero

	BCF		FLAGS_DECO, BIT_BASE
	RETURN
	
_uno

	BSF		FLAGS_DECO, BIT_BASE
	
	RETURN




	ORG 0x2100 
	
EE_S0_MEMORY_SIZE		DE .8
EE_S0_CLOCKS_PER_BIT 	DE .64
EE_S0_TAG_MODE			DE TAG_MODE_CODING_MANCHESTER
EE_S0_RFID_MEMORY		DE 	b'11111111' , b'10001100' , b'01100011' , b'00011000', b'11000110' , b'00110001' , b'10001100' , b'01100000'



	ORG 0x2100 + .1*(MAX_MEMORY_SIZE+.4)

EE_S1_MEMORY_SIZE		DE .12
EE_S1_CLOCKS_PER_BIT 	DE .64
EE_S1_TAG_MODE			DE TAG_MODE_CODING_BIPHASE
EE_S1_RFID_MEMORY		DE	b'00000000', b'11111111', b'11111111', b'00000011', b'11101101', b'11111111', b'11111111', b'11100101', b'00100101', b'11111111', b'11111111', b'11111111'
	


	ORG 0x2100 + .2*(MAX_MEMORY_SIZE+.4)

EE_S2_MEMORY_SIZE		DE .8
EE_S2_CLOCKS_PER_BIT 	DE .64
EE_S2_TAG_MODE			DE TAG_MODE_CODING_MANCHESTER
EE_S2_RFID_MEMORY		DE	b'11111111' , b'10001100' , b'01100011' , b'00011000', b'11000110' , b'00110001' , b'10000000' , b'01100010'	;Bueno - 16



	ORG 0x2100 + .3*(MAX_MEMORY_SIZE+.4)

EE_S3_MEMORY_SIZE		DE .16
EE_S3_CLOCKS_PER_BIT 	DE .32
EE_S3_TAG_MODE			DE TAG_MODE_CODING_BIPHASE
EE_S3_RFID_MEMORY		DE 	b'11111111' , b'11101100' , b'11110011' , b'00000000', b'11111111' , b'00000001' , b'10000000' , b'01110010', b'11111111' , b'10001111' , b'01100011' , b'00011000', b'11000110' , b'00110001' , b'10000110' , b'01101010'

	
	
	ORG 0x2100 + .4*(MAX_MEMORY_SIZE+.4)

EE_S4_MEMORY_SIZE		DE .8
EE_S4_CLOCKS_PER_BIT 	DE .64
EE_S4_TAG_MODE			DE TAG_MODE_CODING_MANCHESTER
EE_S4_RFID_MEMORY		DE 	b'11111111' , b'10001100' , b'01100011' , b'00011000', b'11000110' , b'00110001' , b'10000000' , b'00000000'	;Bueno - 17
	
	

	ORG 0x2100 + .5*(MAX_MEMORY_SIZE+.4)

EE_S5_MEMORY_SIZE		DE .8
EE_S5_CLOCKS_PER_BIT 	DE .64
EE_S5_TAG_MODE			DE TAG_MODE_CODING_MANCHESTER
EE_S5_RFID_MEMORY		DE 	b'11111111' , b'10001100' , b'01100011' , b'00011000', b'11000110' , b'00110001' , b'10001100' , b'01100000'
	


	ORG 0x2100 + .6*(MAX_MEMORY_SIZE+.4)

EE_S6_MEMORY_SIZE		DE .8
EE_S6_CLOCKS_PER_BIT 	DE .64
EE_S6_TAG_MODE			DE TAG_MODE_CODING_MANCHESTER
EE_S6_RFID_MEMORY		DE 	b'11111111' , b'10001100' , b'01100011' , b'00011000', b'11000110' , b'00110001' , b'10000000' , b'00000000'	;Bueno - 17
	


	ORG 0x2100 + .7*(MAX_MEMORY_SIZE+.4)

EE_S7_MEMORY_SIZE		DE .8
EE_S7_CLOCKS_PER_BIT 	DE .64
EE_S7_TAG_MODE			DE TAG_MODE_CODING_MANCHESTER
EE_S7_RFID_MEMORY		DE 	b'11111111' , b'10001100' , b'01100011' , b'00011000', b'11000110' , b'00110001' , b'10000000' , b'00000000'	;Bueno - 17



	ORG 0x2100 + .8*(MAX_MEMORY_SIZE+.4)

EE_S8_MEMORY_SIZE		DE .8
EE_S8_CLOCKS_PER_BIT 	DE .64
EE_S8_TAG_MODE			DE TAG_MODE_CODING_MANCHESTER
EE_S8_RFID_MEMORY		DE 	b'11111111' , b'10001100' , b'01100011' , b'00011000', b'11000110' , b'00110001' , b'10000000' , b'00000000'	;Bueno - 17



	ORG 0x2100 + .9*(MAX_MEMORY_SIZE+.4)

EE_S9_MEMORY_SIZE		DE .8
EE_S9_CLOCKS_PER_BIT 	DE .64
EE_S9_TAG_MODE			DE TAG_MODE_CODING_MANCHESTER
EE_S9_RFID_MEMORY		DE 	b'11111111' , b'10001100' , b'01100011' , b'00011000', b'11000110' , b'00110001' , b'10000000' , b'00000000'	;Bueno - 17



	ORG 0x2100 + .10*(MAX_MEMORY_SIZE+.4)

EE_S10_MEMORY_SIZE		DE .8
EE_S10_CLOCKS_PER_BIT 	DE .64
EE_S10_TAG_MODE			DE TAG_MODE_CODING_MANCHESTER
EE_S10_RFID_MEMORY		DE b'11111111' , b'10001100' , b'01100011' , b'00011000', b'11000110' , b'00110001' , b'10000000' , b'00000000'	;Bueno - 17



	ORG 0x2100 + .11*(MAX_MEMORY_SIZE+.4)

EE_S11_MEMORY_SIZE		DE .8
EE_S11_CLOCKS_PER_BIT 	DE .64
EE_S11_TAG_MODE			DE TAG_MODE_CODING_MANCHESTER
EE_S11_RFID_MEMORY		DE b'11111111' , b'10001100' , b'01100011' , b'00011000', b'11000110' , b'00110001' , b'10000000' , b'00000000'	;Bueno - 17



	ORG 0x2100 + .12*(MAX_MEMORY_SIZE+.4)
	
EE_S_COUNTER	DE .0

	  
	END

