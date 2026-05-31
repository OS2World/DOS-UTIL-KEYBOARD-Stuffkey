   PAGE 80,132
   TITLE "StuffIt, Delayed keyboard stuffer. (C) Terje Mathisen 1989-92"
   Subttl "Stuffkey Vers. 3.3+ enhanced by J.Geist. See below for detalis."
COMMENT `
   
   Ver. 4.00 -  Added {IfSucc}/{IfFail} {Else} {Endif} code. Currently
                {Prompt} and {Find} can be tested for success. This
                requires setting {Timeout}, ~ tilde is short form, before 
                using said functions. If text is found before ~ expires,
                {IfSucces} will be true. Otherwise, commands after
                {Else} or {Endif} will be executed; whichever is found 
                first. No attempt is made to match If-Else-Endifs; they
                are processed as found, based on the "Success" variable.
                Note {IfSucc}={IfTrue}={IfT} and {IfFail}={IfFalse}={IfF}.
   
   Ver. 3.30 -  Renamed this Stuffkey to avoid conflicts with possible
                new version of Stuffit.
             -  Added {Prompt}"easy prompt" that counts string length,
                adds PROMPTADD (3) and uses slop factor of PROMPTSLOP (4).
                Thus, {Prompt}'ptext' would become: 
                {Prompt}8,0,4,'ptext'. Much simpler and usually sufficient.
             -  Added ~ {TimeOot} feature to allow escaping from failed 
                {Find} and {Prompt} commands. Added var. Success for these,
                next version will allow "If Success Goto" commands.
             -  Modified CountDown proc. to read timer ticks, [Bios_Time], 
                as assuming an Int 08 per tick NG in Windows, DV, etc. 
             -  Added '.' no. ticks to time args. i.e., +.3 delays 3 ticks.
             -  Added ERROR MESSAGES - at last!
             *  All modified code is marked. Routines: GetTime, CountDown,
                ScanText; (in Parser) Detime, and ErrorMsg were affected.
ENDCOMMENT `               

VerNr   EQU 400h
VerStr  EQU '4.00'

FALSE   EQU 0                   ;*** V 3.30 (Stuffkey) added TRUE, FALSE, 
TRUE    EQU NOT FALSE           ; PROMPTADD & PROMPTSLOP EQU'S.

PROMPTADD  EQU 3                ;default "easy prompt" dx = strlen + this
PROMPTSLOP EQU 4                ;default "easy prompt" slop factor.
NO_ATTR    EQU 255              ;flag to skip attribute in text searches

        LOCALS                  ; Use TASM features for easier development.
        NOJUMPS

TicksPrDay      EQU 1573041
TicksPrHour     EQU 65543
ResidualTicks   EQU TicksPrDay MOD 0ffffh       ; 201, 0c9h ticks
LastHrTicks     EQU TicksPrHour - ResidualTicks

BIOS SEGMENT AT 40h
        ORG 1Ah
BufferHead      dw ?
BufferTail      dw ?
BufferStart     dw 16 dup (?)
BufferEnd       LABEL word

        ORG 49h
VideoMode       db ?
CrtWidth        dw ?

        ORG 4Eh
CurrStart       dw ?
Cursor          dw ?

        ORG 6Ch
BIOS_Timer      dw 2 dup (?)

        ORG 80h
KbdBufferStart  dw ?
KbdBufferEnd    dw ?

BIOS ENDS

BOOT SEGMENT AT 0F000h
        ORG 0FFF0h
RebootLocation  LABEL FAR
BOOT ENDS

; To reduce the resident size of StuffIt, the script is compressed into tokens
; using the following algorithm:
;
; 0 and 224 are used as the character part of function keys. These codes are
; always followed by a the function key scan code.
;
; 254 is an escape character, followed by a char:scan pair. This is also used
; if we need to enter Chr(254) or Chr(255)
;
; 255 is the lead-in for an extended function code. It will be followed by
; one of these codes:
;
; Codes for extended functions, i.e not normal keys:

REBOOT_CODE     = 0
ATTIME_CODE     = 1
DELTATIME_CODE  = 2
FIND_CODE       = 3
PROMPT_CODE     = 4
PRTSCRN_CODE    = 5
BREAK_CODE      = 6

;*** Some codes added for Stuffkey Ver. 3.30 & up.
;*** See the extended jump table below for definitions.

; Use 255 to signal that the following is an extended function

EXTENDED_CODE   = 255

; Use 254 as lead-in for keys that need both char & scan.

GETWORD_CODE    = 254

; All other codes (1-221,223-253) are presumed to be single characters to
; place in the kbd buffer. All of them will receive the same scan code (2).
; If your application cannot accept this, you must use the {c} or [c] syntax,
; where <c> is any character. This will be translated to the US std enh kbd
; char:scan pair.


CODE SEGMENT PARA PUBLIC 'code'
        ASSUME CS:CODE,DS:NOTHING,ES:NOTHING
        ORG 0
PspStart label byte

        ORG 5Ch
ResidentSize    dw ?

LowStart label byte                     ; Small size TSR

        ORG 80h
CommandLen      db ?
CommandLine     LABEL BYTE

        ORG 100h
start:
        jmp init

Semafor equ 'ST'                        ; Stuffit/Stuffkey

;LowStart label byte                    ; Move this label to decrease size!
HighStart label byte

MoveDown EQU HighStart - LowStart       ; Relocation factor for resident
                                        ; part of StuffIt

Int2F   proc far
        cmp ax,0E000h
         je @@maybe

@@chain:
;       jmp [OldInt2F]
        db 0EAh
OldInt2F dd ?

@@maybe:
        cmp dx,Semafor                  ; Be safe, insist on semafor in DX

current = $
        org $-2
Semafor_1 label word
        org current

         jne @@chain

@@We_Are_Here:
        mov al,0FFh
        mov dx,cs
        mov bx,VerNr

        iret

Int2F   endp


; Here comes the actual, INT 8, code, which will run on every timer tick to
; execute the tokenized script.
;
; To reduce the performance overhead of having StuffIt loaded, I use a dirty
; trick: Self-modifying code.
;
; When the script has finished, the total overhead is reduced to just
; 3 instructions: PUSHF / CALL (FAR IMMEDIATE) OldTimer / IRET

PUSH_AX_OPCODE EQU  50h                 ; Opcode for PUSH AX, used when active
IRET_OPCODE    EQU 0CFh                 ; Opcode for IRET, used when disabled

MyTimer PROC FAR
        pushf
;       call [OldTimer]                 ; Call the old timer code first, to
        db 09Ah                         ; do it's stuff and re-enable the HW.
OldTimer dw ?,?

SelfModify label byte                   ; This will be IRET when idle
        push ax                         ; PUSH AX = 50h, IRET = 0CFh

; The [active] flag is initialized to -1. This way I can use an INC
; instruction to detect the first entry into this code. Multiple
; invocations will jump directly to the exit code, with very little
; overhead. (A total of only 7 instructions and 1 short jump.)

        inc byte ptr [cs:active-MoveDown] ;  INC from -1 to 0
         jnz Already_Active

        STI
        CLD

        push bx
        push cx

        push dx
        push si
        push di
        push ds
        push es

        push cs
        pop ds
        ASSUME DS:CODE

        mov es,[BiosSeg-MoveDown]       ; I store 40h in a memory variable and
        push ds                         ; load ES from it, as this saves one
        push es                         ; instruction vs MOV AX,40/MOV ES,AX
        ASSUME ES:BIOS


        call word ptr [StuffMode-MoveDown]      ; State machine, call the 
        pop es                                  ; current state handler.
        pop ds                                  ; had to save for below...
        cmp byte ptr [TimerOn-MoveDown],False   ; Ver. 3.30. If time out   
        je @@NoTimer                            ; enabled, call CountDown
        call word ptr [TimeoutCheck-MoveDown]   ; else return
@@NoTimer:                                      
        pop es
        pop ds
        pop di
        pop si
        pop dx

        pop cx
        pop bx

        ASSUME CS:CODE,DS:NOTHING,ES:NOTHING

        CLI

Already_Active:

        dec byte ptr [cs:active-MoveDown]

        pop ax
        iret
MyTimer ENDP

        ASSUME CS:CODE,DS:CODE,ES:BIOS

StuffFinished:
        mov [SelfModify-MoveDown],IRET_OPCODE   ; Disable by self-modifying
                                        ; May be re-enabled by a later
                                        ; invocation of StuffIt.
        ret

NextKey proc near
        mov si,[StuffPtr-MoveDown]
GetNext:
        cmp si,[StuffEnd-MoveDown]
         jae StuffFinished

        lodsb
        cmp al,GETWORD_CODE
         ja Extended                    ; Extended function
         je @@GetBoth                   ; 254 => char, scan follows

        mov ah,2                        ; Simulate scan = 2 for normal chars
        cmp al,224                      ; Character for Enh.Kbd new keys
         je @@GetScan

        or al,al
         jne stuff

@@GetScan:
        mov ah,[si]
        inc si
         jmp short stuff

@@GetBoth:
        lodsw
Stuff:
        CLI
        mov di,[BufferTail]
        stos word ptr [BIOS:di]
        cmp di, OFFSET BufferEnd

BufferEndAddr label word

         jb @@1
        mov di, OFFSET BufferStart
BufferStartAddr label word
@@1:
        cmp di,[BufferHead]
         je @@Overflow
        mov [BufferTail],di
        STI
StuffOK:
        mov [StuffPtr-MoveDown],si
         jmp GetNext

@@OverFlow:
        STI
        ret
NextKey ENDP

ExtendedTable label word
  dw Reboot      - MoveDown
  dw AbsTime     - MoveDown
  dw DeltaTime   - MoveDown
  dw StartFind   - MoveDown
  dw StartPrompt - MoveDown
  dw PrtScrn     - MoveDown
  dw CtrlBreak   - MoveDown

;**** These routines added for Ver. 3.30 (Stuffkey)  

SETTIMEOUT_CODE = ($ - offset ExtendedTable) SHR 1  
  dw SetTimeOut  - MoveDown

;**** These routines added for Ver. 4.00 (Stuffkey)  
IFSUCCESS_CODE = ($ - offset ExtendedTable) SHR 1   
  dw IfSuccess   - MoveDown
IFFAIL_CODE = ($ - offset ExtendedTable) SHR 1   
  dw IfFail   - MoveDown
ELSE_CODE = ($ - offset ExtendedTable) SHR 1  
  dw ElseSuccess - MoveDown
ENDIF_CODE = ($ - offset ExtendedTable) SHR 1  
  dw EndSuccess  - MoveDown
STOP_CODE = ($ - offset ExtendedTable) SHR 1  
  dw StopScript - MoveDown


COMMENT `  
  dw ScrollPause - MoveDown
SCROLLPAUSE_CODE = ($ - offset ExtendedTable) SHR 1    
  dw RepeatSet   - MoveDown
REPEATSET_CODE = ($ - offset ExtendedTable) SHR 1    
  dw RepeatLoop  - MoveDown
REPEATLOOP_CODE = ($ - offset ExtendedTable) SHR 1    
  dw StartProc   - MoveDown
STARTPROC_CODE = ($ - offset ExtendedTable) SHR 1    
  dw EndProc     - MoveDown
ENDPROC_CODE = ($ - offset ExtendedTable) SHR 1    
  dw VarPause    - MoveDown
VARPAUSE_CODE = ($ - offset ExtendedTable) SHR 1    
  dw FixedPause  - MoveDown
FIXEDPAUSE_CODE = ($ - offset ExtendedTable) SHR 1    
ENDCOMMENT `
;*** end 3.30 adds.

NrOfCodes = ($ - offset ExtendedTable) SHR 1

Extended PROC near
        lodsb                           ; Get function code!
        cmp al,NrOfCodes
        jae StuffFinished               ; Program Error! Abort the script!

        cbw                             ; All codes are <= 127, so CBW is OK!
        mov bx,ax
        shl bx,1
        jmp ExtendedTable[bx - MoveDown] ; Jump to function handler

Extended endp

; **** Ver 4.00 - (Stuffkey) IfSuccess code. 
;   Tests if Success is true. (or false for IfFail code). 
;   If true, continues processing following keys/tokens.
;   If not, resumes at token following next {Else} or {Endif}, respectively.
;   No attempt is made to match If-Else-Endifs, they are dealt with as
; they are discovered. An unexpected {Else} will cause program to continue
; execution after the first {Endif} found. {Endif}'s are always skipped.
; ****
IfSuccess Proc  near
IfFail:                                 ; handle both If's here        
        mov bl,IFSUCCESS_CODE           ; default "If" code
        mov bh, [Success - MoveDown]    ; get "Success" True/False
        cmp al,bl                       ; Success or Fail code?
        jne @@IfF                       ; Avoid a jump for common IfSuccess
        xor bh,True                     ; invert "Success" flag
@@IfF:                                  
        xor bh,True                     ; invert, back to True, nz, if IfSucc.
        jz  @@NotSuccess
        jmp GetNext
ElseSuccess:                            ; pull a Terje, sorta fits..
        mov bl,al                       ; save "else" code
@@NotSuccess:
        lodsb                           ; get next byte in buffer
        cmp si,[StuffEnd-MoveDown]      ; ensure we haven't overrun buffer
         jae StopScript
        cmp al, EXTENDED_CODE           ; does it look like an ext. token?
        jne @@NotSuccess                ; nope, loop.
        mov ax, [si]                    ; else pick up next word
        cmp ax, ENDIF_CODE * 256 + ENDIF_CODE
        je @@double_check
        cmp ax, ELSE_CODE  * 256 + ELSE_CODE
        jne @@NotSuccess                ; if we get past this, have found
        cmp bl, IFSUCCESS_CODE          ; {Else}; only allowed if last
        jne @@NotSuccess                ; command was IfSuccess
@@double_check:
        cmp byte ptr [si+2], EXTENDED_CODE      ;** Improve if/else code ?
        jne @@NotSuccess
        lodsw
        lodsb
        jmp GetNext                     ; continue processing
IfSuccess Endp

EndSuccess Proc near
        lodsw
        jmp GetNext
EndSuccess endp

StopScript Proc Near
        jmp StuffFinished
StopScript Endp

; **** Ver 3.30 - changed to Cold boot - better in Desqview & Windows.
; this code definitely needs help in the multitasking and disk cache 
; flushing! J.Geist 6Oct92.
Reboot proc near
        mov word ptr [BIOS: 72h],1234h  ; == Warm Boot (CtrlAltDel)
        mov word ptr [BIOS: 72h],0      ; == Cold Boot (Reset button)
        jmp RebootLocation              ; == F000:FFF0
Reboot endp

PrtScrn proc near
        int     5
        jmp     GetNext
PrtScrn endp

CtrlBreak proc near
        int     1Bh
        xor     ax,ax
        jmp     Stuff
CtrlBreak endp

AbsTime:                                ; Both Abs time & Delta time land here
DeltaTime:                              ; ---- " ----
SetTimeOut:                             ; Ver. 3.30 TimeOut too.
;*** Ver. 3.30 (J.G.) modified GetTime a fair bit.
GetTime proc near
        mov [Success-MoveDown],False
        mov word ptr [TimeoutVars - MoveDown], False
;        mov [TimedOut-MoveDown],False  ; above word move takes care of
;        mov [TimerOn-MoveDown],False   ; of these two prev byte moves.
        cmp al,SETTIMEOUT_CODE
        jne @@NotTimer
        mov [TimerOn-MoveDown], True
@@NotTimer:
        cmp al, ATTIME_CODE
        lodsw                           ; Next 3 bytes is # of ticks
        mov dl,[si]
        jnz @@TimeOk                    ; Delta time, so wait # of ticks

; Wait until time equal: Calculate remaining ticks
        
        sub ax,[Bios_Timer]
        sbb dl,BYTE PTR [Bios_Timer+2]
         jae @@TimeOk

        add ax,TicksPrDay AND 0FFFFh
        adc dl,TicksPrDay Shr 16

@@TimeOK:
        inc si
        mov [StuffPtr-MoveDown],si      ; Point to next byte

        sub dh,dh                       ; Fill top of DX with 0
        or ax,dx
        jz @@WaitZero                   ; Special case, wait for empty kbd

        mov [CountLow-MoveDown],ax      ; Save # ticks to wait, low word.
        mov [CountHigh-MoveDown],dl     ; and # ticks hi byte.

;*** 3.30. Relying on Int 08 every timer tick NG in DV, Windows, etc.
;          now reading Bios_Timer, using actual elapsed ticks.        

        mov ax,[Bios_Timer]             ; Recover current low ticks.
        mov [OldTicks-MoveDown],ax      ; and save.
        cmp [TimerOn-MoveDown], False   ; Check if timeout desired
        je @@SetCount                   ; Set up for countdown if Timer off.
                                        ; else set up for next key.
        mov [StuffMode-MoveDown], OFFSET NextKey - MoveDown
        ret
@@SetCount:        
        mov [StuffMode-MoveDown], OFFSET CountDown - MoveDown
        ret

@@WaitZero:
        mov [TimerOn-MoveDown],False
        mov [StuffMode-MoveDown], OFFSET WaitEmpty - Movedown
        ret
GetTime endp

CountDown proc near
        mov ax, [Bios_Timer]            ; 3.30 Get current ticks
        mov bx, [OldTicks-MoveDown]     ; get last tick count
        mov [OldTicks-MoveDown], ax     ; update old tick count.
        SUB ax, bx                      ; calc. REAL #ticks gone by.
        ja @@NoLWrap                    ; low ticks wrapped if below
;** check for new day here when low count wraps
        cmp [Bios_Timer+2],0            ; new day if high ticks = 0
        jne @@NoLWrap                   ; adjust low ticks if so
        add ax, ResidualTicks           ; we lose these ticks at day-wrap.
@@NoLWrap:
        SUB [CountLow-MoveDown], ax     ; Subtract elapsed ticks
        ja @@NoChange                   ; If above, continue
        jnz @@DecHi                     ; if non zero, dec hi count
        DEC [CountLow-MoveDown]         ; special case for 0
@@DecHi:         
        SUB [CountHigh-MoveDown],1
         jae @@NoChange
        cmp [TimerOn-MoveDown], True
        jne @@StartNextKey
        mov [TimerOn-MoveDown], False
        mov [TimedOut-MoveDown], True
        ret
; **** 3.30. Admittedly Terje's coding saves bytes..but I sure don't like
;            'jumping' in & out of proc's - like WaitEmpty jumps to this
;            this label....oh well. JG.
StartNextKey:
@@StartNextKey:
        mov [StuffMode-MoveDown], OFFSET NextKey - MoveDown
@@NoChange:
        ret
CountDown endp

WaitEmpty proc near
        mov ax,[BufferHead]
        cmp ax,[BufferTail]
        je StartNextKey
        ret
WaitEmpty endp

StartPrompt:
        mov [Success-MoveDown], False
        mov [StuffMode-MoveDown], offset ScanPrompt - MoveDown
        mov [StuffPtr-MoveDown],si

; si -> dx:BYTE, dy:BYTE, count:WORD, len:BYTE, attr:BYTE, st:BYTE * len

ScanPrompt:                             ; Find start posn'n

        mov si,[StuffPtr-MoveDown]

        lodsw                           ; AL = dx, AH = dy
        mov cx,[Cursor]                 ; CL = X,  CH = y
        sub cl,al
         jae @@1
        sub cl,cl
@@1:
        sub ch,ah
         jae @@2
        sub ch,ch
@@2:
        mov al,byte ptr [CrtWidth]
        mul ch                          ; AX = Y-offset
        sub ch,ch
        add ax,cx
        shl ax,1                        ; AX = Start of scan

         jmp short Scan1

StartFind:
        mov [Success-MoveDown], False
        mov [StuffMode-MoveDown], offset ScanText - MoveDown
        mov [StuffPtr-MoveDown],si

; si -> start:WORD, count:WORD, len:BYTE, attr:BYTE, st:BYTE * len

ScanText proc near

        mov si,[StuffPtr-MoveDown]
        lodsw                           ; starting offset in screen

Scan1:
        mov di,ax
        lodsw
        mov cx, ax                      ; # of char cells to search

        lodsw                           ; AL = len, AH = attr
        mov dl,al
        xor dh,dh                       ; Text len

        dec dx                          ; Skip first char in length

        mov bx, 0B000h
        cmp [VideoMode],7
         je @@1
        cmp [VideoMode],3
         ja @@done
        mov bh,0B8h
@@1:
        mov es,bx                       ; ES -> video segment
ASSUME ES:NOTHING

        inc si                          ; Skip first char
        cmp ah,255                      ; ATTR = 255 -> no attr
         je @@FindChar

@@FindCharAttr:
        mov al,[si-1]                   ; First char to match
  repne scasw
         jne @@done
        or dx,dx                        ; Remaining length = 0
         jz @@found

        push cx
        push si
        push di
        mov cx,dx
@@l2:
        lodsb
        scasw
         loope @@l2

        pop di
        pop si
        pop cx
         je @@found                     ; Yes, all chars match!
         jcxz @@done                    ; No more room!
         jne @@FindCharAttr             ;  this BUG was found by rbabcock!

@@FindChar:
        mov al,[si-1]
        dec di
@@l3:
         jcxz @@done                    ; No more room to start in!
@@l31:
        inc di
        scasb
         loopne @@l31

         jne @@done

        or dx,dx
         jz @@found

        push cx
        push si
        push di
        mov cx,dx
@@l4:
        inc di
        cmpsb
         loope @@l4

        pop di
        pop si
        pop cx
         jne @@l3

@@found:
        mov [Success-MoveDown],True     ; Flag a succesful find/prompt
@@FoundRet:        
        mov word ptr [TimeOutVars-MoveDown], False
; ** above covers both bytes in next two commented out lines. V 3.30
;        mov [TimedOut-MoveDown], False
;        mov [TimerOn-MoveDown], False
        add si,dx                       ; Point after text to search for
        mov [StuffMode-MoveDown], offset NextKey - MoveDown
        mov [StuffPtr-MoveDown],si
        ret
@@done:
        cmp [TimedOut-MoveDown],True
        je @@FoundRet
        ret
ScanText Endp

        ALIGN 2

BiosSeg         dw 40h

FirstByteToCopy label byte

StuffPtr        dw OFFSET StuffBuffer - MoveDown
StuffEnd        dw ?
StuffMode       dw OFFSET NextKey - MoveDown
TimeOutCheck    dw OFFSET CountDown - MoveDown

TimeoutVars     label word              ; Used to access next two as word,
TimerOn         db False                ; TimerOn low & TimeOut hi.
TimedOut        db False                ; DO NOT REARRANGE THESE THREE!

Success         db False
ScrollPause     db True
CountLow        dw ?
CountHigh       db ?                    ; Use 24 bits for tick counter
OldTicks        dw ?
active          db -1

ResidentEnd     EQU $

StuffBuffer     LABEL byte

StartMsg db 'Stuffkey ',VerStr," J.Geist's enhancements to "
         db "T.Mathisen's StuffIt 3.21 (C) 1989-92."
         db 13,10,'$'

UsageMsg label byte
db 13,10
db 'Syntax: Stuffit/Stuffkey <commands>',13,10
db ' +|=|~[[hh:]mm:]ss : Delay (+), until(=), timeout in(~) a specified time.',13,10
db '        or             +5 waits 5 secs. +.5 waits 5 timer ticks.,',13,10
db '      +|~.nn           =14:: waits til 2pm. +0 til kbd buffer empty.',13,10
db '                       ~1: will timeout next {Find}, {Prompt} in 1 min.',13,10                             
db " 'TEXT'",' or "TEXT"     : Stuff all the characters in TEXT',13,10
db ' {KeyName} (/L lists) : {F1}, [sF1], {^Left}, {Home}, [Reboot], {Prompt}, etc.',13,10
db ' <char>[:<scan>]      : Char. code. 27=<Esc>, 13=<CR>, 43:74=<Num+>,  etc.',13,10
db ' @<scan code>         : Stuff a given scan code (char=0). @68=F10,@73=PgUp etc.',13,10
db ' Fx,y,n[,attr],"TEXT" : Find "TEXT" in an area starting at (X,Y),',13,10
db "  (or {Find}x,y etc)     and being (N) char's long. (Top left = 1,1)",13,10
db ' P[dx,dy,n[,attr],]"TEXT" : Find "TEXT", relative to (behind) cursor. ie:',13,10
db '  (or {Prompt} etc)     P"ID: " = P7,0,4,"ID: " finds ID: @curs X -7 to -4.',13,10
db ' {IfSucc} {Else} {Endif}  : Use with {Timeout} {Prompt} & {Find}. See docs!',13,10
db '-------------------- Command Line Startup Options ----------------------',13,10
db ' /F:File  : Read cmds from <File>.   /L    : List mnemonic key names.',13,10
db ' /B:nnn   : Buffer size. 512 def.    /Sab  : "ab" vs."ST" signature. ',13,10
db ' /R       : Remove pgm from RAM.     /E    : Expanded kbd ptrs 40:80, 82',13,10
;** add /Q quit in next ver! 4.01?  
; db ' /Q       : Quiet mode, except errs.',13,10
db '$'


;************************************************************************
;            Error messages - added in Stuffkey 3.30 - J. Geist
;*************************************************************************
LinErrMsg db '** Error lin# $'

EndStrMsg label byte
CRLF db 13,10,'$'

UpdateMsg       db 'Resident copy updated!',13,10,'$'

StayResMsg      db 'Resident code loaded!',13,10,'$'

RemovedMsg      db 'Resident code removed from RAM!',13,10,'$'

WrongVerMsg db 'A different version of StuffIt/Stuffkey is already resident!'
            db 13,10,'$'

NotRemovedMsg  label byte
 db 'Resident code cannot be removed, as another '
 db   'program is using the',13,10
 db 'Timer (Int 8) and/or the Multiplex (Int 2F) '
 db   'vector. Please remove all',13,10
 db 'programs loaded after StuffIt/Stuffkey, '
 db   'and retry the operation.',13,10,'$'

RamErrMsg label byte
 db 'Not enough RAM! (Need at least 128 kB to initialize program.)',13,10,'$'

FileErrMsg label byte
 db 'Error reading input file!',13,10,'$'

ResidentToSmallMsg label byte
 db 'Resident buffer to small! Try to remove it (/R) and reload.',13,10,'$'

;*** Error_msg's added in Stuffkey v3.30 - J.Geist
InvalidMsg      db ' Invalid ','$'
ExtraErrMsg     db ' Bad ','$'
BadTokenMsg     db 'Token. ','$'
BadTimeMsg      db 'Time. ','$'
BadFindMsg      db 'Find string cmd. ','$' 
BadPromptMsg    db 'Prompt find cmd. ','$'
BadParmMsg      db 'or missing parameter(s). ','$'
BadStringMsg    db 'String or closing quote(s). ','$'
BadNumMsg       db 'number. ','$'
BadRangeMsg     db 'number - out of range. ','$'
RemNresErrMsg   db '/R removal requested - program is NOT resident. ','$'
BadCmdOptMsg    db 'Command line options. ','$'
UndefErrMsg     db 'or unknown command. ','$'
;*** end of added error msgs in v3.30

;FirstBlock      dw ?
;SecondBlock     dw ?
 
        JUMPS        ; Allow inefficient code in transient part of code!
                     ; This makes it more readable.

Init proc near
ASSUME DS:CODE, ES:CODE

        mov     ax,OFFSET StuffBuffer - MoveDown + 512 + 15
        and     ax,0FFF0h
        mov     [ResidentSize], ax

; Start by relocating the program into a second segment

;        mov     [FirstBlock],CS         ; Save segment addr

        mov     ah,4Ah
        mov     bx,2000h                ; Realloc to 128 kB
;       mov     es,[FirstBlock]
        int     21h
        mov     dx, offset RamErrMsg
         jc     ErrorMessage

;        mov     ah,48h
;        mov     bx,1000h
;        int     21h                     ; Alloc second 64kB block
;        mov     dx, offset RamErrMsg
;         jc     ErrorMessage

        mov     ax,cs
        add     ax,1000h                ; Point after 1st 64kB

        mov     es,ax
;        mov     [SecondBlock],es
        sub     si,si
        mov     di,si
        mov     cx,(OFFSET ProgramEnd - OFFSET PspStart + 1) Shr 1
        cld
        rep     movsw

        push    es
        mov     ax, OFFSET Continue
        push    ax
        retf

;        pop     cs                      ; Jump into second copy of program!
Continue:
        push    ds
        push    cs
        pop     ds
        pop     es                      ; DS=CS = SecondBlock, ES=FirstBlock

; Move resident part of code as low as possible:

        mov     si, OFFSET HighStart
        mov     di, OFFSET LowStart
        mov     cx, OFFSET ResidentEnd - OFFSET HighStart
        rep     movsb

        mov dx, OFFSET StartMsg
        mov ah,9
        int 21h
        mov ax, OFFSET UndefErrMsg      ; Init error msg as undefined.
        mov SynErrMsg,ax
        call Parse

        cmp di, OFFSET StuffBuffer - MoveDown
        mov dx, offset UsageMsg
         je ErrorMessage                ; No parameters!

        push    es
        pop     ds                      ; DS,ES,SS = FirstBlock

        mov [StuffEnd-MoveDown],di
;       mov [StuffMode-MoveDown], OFFSET NextKey - MoveDown
;       mov [StuffPtr-MoveDown], OFFSET StuffBuffer - MoveDown

;       mov [active-MoveDown],-1                 ; Initialize [active] flag
;       mov [BiosSeg-MoveDown],40h               ; Fast load of ES: when resident

        call TestSecond                 ; Don't return if second copy!

; Get old int 2F interrupt

        mov ax,352Fh
        int 21h
        mov WORD PTR [OldInt2F-MoveDown],BX
        mov WORD PTR [OldInt2F+2-MoveDown],ES

; Get old timer interrupt
        mov ax,3508h
        int 21h
        mov WORD PTR [OldTimer-MoveDown],BX
        mov Word Ptr [OldTimer+2-Movedown],ES

; Enter our routine first

        mov ax,252Fh
        mov dx, OFFSET Int2F - MoveDown
        int 21h

        mov ax,2508h
        mov dx, OFFSET MyTimer - MoveDown
        int 21h

        mov ES, [DS:2Ch]
        mov ah,49h
        int 21h
        mov word ptr [DS:2Ch],0         ; Signal no environment!

        push ds
        push cs
        pop ds
        mov dx, OFFSET StayResMsg
        mov ah,9
        int 21h
        pop ds

        mov cx,5
@@CloseLoop:
        mov bx,cx
        dec bx
        mov ah,3Eh
        int 21h
         loop @@CloseLoop

        push ss
        pop ds
        mov dx, [DS:ResidentSize]
        cmp dx, [DS:Stuffend-MoveDown]
         ja @@OK
        mov dx, [DS:StuffEnd-MoveDown] ; DX = MAX(ResidentSize, StuffEnd)
        mov [DS:ResidentSize],dx
@@OK:
        add dx,15
        mov cl,4
        shr dx,cl
        mov ax,3100h
        int 21h                         ; Go TSR with first block

Init Endp

FindFirst proc near

        mov dx,Semafor
current = $
        org $-2
Semafor_2 label word
        org current

        mov ax,0E000h
        xor bx,bx
        int 2Fh

        cmp al,0FFh
         jne @@done

        cmp bx, VerNr
         je @@done

        mov dx, offset WrongVerMsg
         jmp ErrorMessage

@@done:
        ret                             ; Return ZERO if found

FindFirst endp

TestSecond proc near
        call FindFirst
         jne @@NotFound

        mov es,dx                       ; Save segment

; This is the second copy! ES -> to first copy
; Test if enough room in resident program:

        mov ax,[StuffEnd-MoveDown]
        cmp ax,[ES:ResidentSize]
        mov dx, OFFSET ResidentToSmallMsg
         ja ErrorMessage

; Will now move all data into first copy, including pointers and StuffMode

        mov [ES:SelfModify-MoveDown], IRET_OPCODE ; Stop resident program
        mov [DS:SelfModify-MoveDown], IRET_OPCODE ; Stop this version!

        mov si, offset FirstByteToCopy - MoveDown
        mov di, si
        mov cx, ax                      ; [StuffEnd]
        sub cx,si
        rep movsb

        mov [ES:SelfModify-MoveDown], PUSH_AX_OPCODE ; Restart resident version

        mov dx, OFFSET UpdateMsg
        mov ah,9
        int 21h

        mov ax,4C00h
        int 21h

@@NotFound:
ParseFinish:
        ret

TestSecond ENDP

LocalSyntax:
        jmp Syntax

EOF     EQU 26
LF      EQU 10                  ; Use LineFeed to count lines

LineNr          dw      ?
StartLineDW    Label Dword      ; Ver 3.30. Holds ptr to beg. of parsed line    
StartLine       dw      ?       ; Offset of above...do not move!
StartLineSeg    dw      ?       ; SEGment of above...not sure if need this...
StartItem       dw      ?       ; ptr to beg of parsed item
ErrLoc          dw      ?       ; ptr to loc where parser gave up
SynErrMsg       dw      ?       ; ptr to appropriate error message.
BadNum          db      False   ; flag for bad number
BadRange        db      False   ; flag for bad numeric range
BadParm         db      False   ; flag for bad or missing params
BadString       db      False   ; flag for bad string - as a param usually.

Parse Proc near
        cld
        mov si, OFFSET CommandLine

        mov bl,[si-1]
        sub bh,bh
        mov word ptr [si+bx],13 + (EOF * 256) ; EOF is ending marker

RestartParse:
        mov di, OFFSET StuffBuffer - MoveDown

        mov     [LineNr],0
NewLine:
        inc     [LineNr]
        mov     StartLine, si
ParseNextChar:
        mov     StartItem, si
        mov     ErrLoc, si
        mov     SynErrMsg, OFFSET UndefErrMsg
        lodsb

        cmp al,EOF
         je ParseFinish

        cmp     al,LF
         je     NewLine                 ; LF marks the end of one line

        cmp     al,';'                  ; ';' makes the rest of the line a
         je     @@Comment               ; comment

        cmp     al,' '
         jbe    ParseNextChar

        cmp al,'0'
         jb @@NotDigit
        cmp al,'9'
         ja @@NotDigit
@@Digit:
        dec si
        mov bx,255
        call GetNumber
        cmp al,':'
        mov al,bl
        mov ah,2
         jne @@NotTwo

        push ax
        mov bx,255
        call GetNumber
        cmp al,':'
         je LocalSyntax

        pop ax
        mov ah,bl

@@NotTwo:
        Call SaveChar
         jmp ParseNextChar

@@Comment:
        lodsb

        cmp     al,EOF
         je     ParseFinish

        cmp     al,13
         je     ParseNextChar

        cmp     al,LF
         jne    @@Comment

        jmp     NewLine

@@NotDigit:
        cmp al,'/'
         je ParseOption
        cmp al,'-'
         je ParseOption

        cmp al,'@'
        jne @@NotFunc
        mov bx,255
        call GetNumber
        mov ah,bl
        xor al,al
        stosw
         jmp ParseNextChar

@@NotFunc:
        cmp al,"'"
         je @@Quote
        cmp al,'"'
         jne @@NotQuote
@@Quote:
        mov bl,al                       ; Save starting quote char
        mov StartItem, si               ; 3.30 save ptr to item in our seg.
@@2:
        lodsb
        cmp al,13                       ; Missing last quote
         je @@MisQuote                  ; Flag the error
        cmp al,bl                       ; Ending quote?
         je ParseNextChar               ; Yes, restart
        mov ah,2                        ; Assume scan = 2
        call SaveChar
         jmp @@2
@@MisQuote:                             ; Ver 3.30 added error msgs.
        mov SynErrMsg, OFFSET BadStringMsg
        mov ErrLoc, si
        jmp Syntax
@@NotQuote:
        cmp al,'~'
         jne @@2_5
         jmp TimeOut
@@2_5:        
        cmp al,'+'
         jne @@3
         jmp DeTime
@@3:
        cmp al,'='
         jne @@4
         jmp AtTime

@@4:
; Use ! to signal Reboot
        cmp al,'!'
         je SignalReboot

        cmp al,'f'
         je FindNear
        cmp al,'F'
         je FindNear

        cmp al,'p'
         je PromptNear
        cmp al,'P'
         je PromptNear

        cmp  al,'{'                     ; Start of token!
         je  StartToken
        cmp  al,'['                     ; Start of token!
         je  StartToken

; Fall into syntax error!
        mov SynErrMsg, OFFSET UndefErrMsg
        mov ErrLoc, si
Parse endp
; ******************************************************************
; Syntax error handling. Much modified in Stuffkey 4.00. Now points
; to Startitem and Errloc with ^---^, if possible.
; 1Nov92 J.Geist
; *******************************************************************
Syntax Proc near
        push    cs
        pop     ds

        mov     dx, OFFSET UsageMsg             ; display usage help
        mov     ah,9
        int     21h
        
        mov     dx, OFFSET EndStrMsg            ; CRLF
        mov     ah,9
        int     21h

;        lds     si, StartLineDW                 ; Ver. 3.30. Get source line 
        mov     si,StartLine
        mov     cx,132                          ; display max 132 chars of it
@@DspLine:        
        lodsb                                   ; get a char from source
        cmp     al,20h                          ; quit on non-disp chars
        jb      @@DspDone
        mov     ah,2                            ; Dos display char.
        mov     dl,al
        int     21h
        loop    @@DspLine
@@DspDone:        
;        push    cs                              ; Restore ds = cs
;        pop     ds                              ; just in case...
        mov     dx, OFFSET EndStrMsg            ; CRLF
        mov     ah,9
        int     21h
        mov     ax,StartItem
        mov     bx,StartLine
        sub     ax,bx                           ; StartLoc displayable ?
        jb      @@BadErrLoc
        je      @@DsplyStart
        cmp     ax,132
        ja      @@BadErrLoc
        mov     cx,ax
@@StartLoc:
        mov     ah,2
        mov     dl,' '
        int     21h
        loop    @@StartLoc
@@DsplyStart:        
        mov     ah,2
        mov     dl,'^'
        int     21h                             ; Point at error with ^
        mov     ax,ErrLoc
        mov     cx,ax
        sub     ax, StartLine
        jbe     @@BadErrLoc
        cmp     ax,132
        ja      @@BadErrLoc
        dec     cx                              ; A slight problem here
        dec     cx                              ; with counting to end of
        sub     cx,StartItem                    ; errored item. V4.00
        jbe     @@BadErrLoc
@@ErrLoc:
        mov     ah,2
        mov     dl,'-'
        int     21h
        loop    @@ErrLoc
        mov     ah,2
        mov     dl,'^'
        int     21h                             ; Point at error with ^
@@BadErrLoc:        
        mov     dx, OFFSET EndStrMsg            ; CRLF
        mov     ah,9
        int     21h

        mov     dx, OFFSET LinErrMsg
        mov     ah,9
        int     21h

        mov     ax,LineNr
        xor     cx,cx
        call    PrintAX
        mov     dx, OFFSET InvalidMsg
        mov     ah,9
        int     21h
        mov     dx,SynErrMsg
        mov     ah,9
        int     21h
        cmp     BadNum, True
        mov     dx, OFFSET BadNumMsg
        jz      @@ExtraError
        cmp     BadRange, True
        mov     dx, OFFSET BadRangeMsg
        jz      @@ExtraError
        cmp     BadParm, True
        mov     dx, OFFSET BadParmMsg
        jz      @@ExtraError
        cmp     BadString, True
        mov     dx, OFFSET BadStringMsg
        jnz     @@ExtraDone

@@ExtraError:
        push    dx
        mov     dx, OFFSET ExtraErrMsg
        mov     ah,9
        int     21h
        pop     dx
        mov     ah,9
        int     21h
@@ExtraDone:
        mov     dx, OFFSET EndStrMsg

ErrorMessage:                   ; straight to here on "option" errors
        push    cs
        pop     ds
        mov     ah,9
        int     21h
        mov     ax,4C01h
        int 21h
Syntax Endp

StartToken:
        mov     StartItem, si   ; 3.30 error displaying
        push    es di

        push    ds
        pop     es

        call    GetToken        ; Return token, with orig. case if a single
        call    FindToken       ; letter, then look it up.
        pop     di es
        jnc     @@TestExtended  ; 3.30 error handling
        mov     SynErrMsg, OFFSET BadTokenMsg
        mov     ErrLoc, si
        jmp     Syntax
@@TestExtended:
        cmp     al,EXTENDED_CODE
         je     @@SaveExtended

        call    SaveChar
        jmp     ParseNextChar

@@SaveExtended:
; **** Stuffkey V.4.00 supports extended codes {IfSucc}, {Else}, {Endif}
;      as of 19 Oct 92, {IfSucc} is simply stuffed; {Else} and {Endif}
;      are "double stuffed" - a temporarily crude way to mark them unique.
;
;        cmp    ah,IFSUCCESS_CODE
;         je    @@Save2                 ; or wherever you want..
        cmp    ah,ELSE_CODE
         je    @@DoubleStuff            ; need to mark else & endif so
        cmp    ah,ENDIF_CODE            ; if & else can find them...
         jne   @@NotIfCode              ; crude in 4.0 - improve! JG.
@@DoubleStuff:
        stosw
        xchg    al,ah                   ; store code again, need it in al
        stosw
        xchg    al,ah                   ; put it back...just in case?
        Jmp     ParseNextChar
; **** end Stuffkey V.4.00 additions.
        
@@NotIfCode:
        cmp     ah,ATTIME_CODE
         je     AtTime
        cmp     ah,DELTATIME_CODE
         je     DeTime
        cmp     ah,SETTIMEOUT_CODE
         je     TimeOut
        cmp     ah,FIND_CODE
         je     FindNear
        cmp     ah,PROMPT_CODE
         je     PromptNear
;        cmp     ah,PRTSCRN_CODE
;         je     @@Save2
;        cmp     ah,REBOOT_CODE
;         je     @@Save2
;

@@Save2:
        stosw
        jmp     ParseNextChar

FindNear:
        jmp FindText

PromptNear:
        jmp PromptText

SignalReBoot:
        mov ax,EXTENDED_CODE + (REBOOT_CODE * 256)
        stosw
         jmp ParseNextChar

ReadFile proc near

        cmp byte ptr [si],':'
         jne @@Skip
        inc si
@@Skip:
        mov dx,si
@@Next:
        lodsb
        cmp al,' '
         ja @@Next
        dec si

        mov ax,3D00h                    ; Open file for Read_Only
        mov byte ptr [si],al            ; Make ASCIIZ filename

        int 21h
        mov dx, OFFSET FileErrMsg
        jc ErrorMessage

        mov bx,ax
        mov ah,3Fh                      ; Read File
        mov dx, OFFSET ProgramEnd
        mov si,dx
        mov cx, - (OFFSET ProgramEnd)   ; Max Size in segment
        int 21h
        mov dx, OFFSET FileErrMsg
         jc ErrorMessage

        add si, ax
        mov byte ptr [si],EOF
        sub si, ax                      ; Point back to start of filebuffer

        mov ah,3Eh
        int 21h                         ; Close this file

         jmp RestartParse               ; Parse file buffer!
ReadFile endp

SetBufferSize proc near

        cmp byte ptr [si],':'
         jne @@Skip
        inc si
@@Skip:
        mov bx,-( OFFSET StuffBuffer - MoveDown) + 32; Max text buffer
        call GetNumber
        add bx,OFFSET StuffBuffer - MoveDown + 15
        and bx,0FFF0h
        mov [ES:ResidentSize],bx
         jmp ParseNextChar

SetBufferSize endp

SetSemafor proc    near
        lodsw
        mov [es:Semafor_1 - MoveDown],ax
        mov [Semafor_2],ax
         jmp ParseNextChar
SetSemafor endp

UseExpandedBuffer proc near
        push ds
        mov ds,[BiosSeg]

        mov ax,[DS:KbdBufferStart]      ; Keyboard Buffer start address
        mov [ES:BufferStartAddr-2-MoveDown],ax
        mov ax,[DS:KbdBufferEnd]        ; Keyboard Buffer end address
        mov [ES:BufferEndAddr-2-MoveDown],ax

        pop ds
         jmp ParseNextChar
UseExpandedBuffer endp

ParseOption Proc near
        mov StartItem, si               ; 3.30 error hndl. Save ptr to 
        lodsb                           ; current parsing area/item
        cmp al,'a'
         jb @@Upper
        cmp al,'z'
         ja @@Upper
        sub al,'a'-'A'
@@Upper:
        cmp al,'B'
         je SetBufferSize
        cmp al,'F'
         je ReadFile
        cmp al,'L'
         je ListKeys
        cmp al,'S'
         je SetSemafor
        cmp al,'E'
         je UseExpandedBuffer
        cmp al,'R'
         je @@Remove                     ; 3.30 more error handling
        mov SynErrMsg, OFFSET BadCmdOptMsg
        mov ErrLoc, si
        jmp Syntax
@@Remove:
        call FindFirst
         jz @@TryRemove
        mov SynErrMsg, OFFSET RemNresErrMsg
        mov ErrLoc, si                 ; Setup to show error message,
        jmp Syntax                     ; First copy, nothing to remove!
@@TryRemove:
        mov ax,3508h
        int 21h
        cmp bx, OFFSET MyTimer - MoveDown
         jne @@CannotRemove
        mov ax, es
        cmp ax, dx
         jne @@CannotRemove             ; Other TSR has timer vector!

        mov ax,352Fh
        int 21h
        cmp bx, OFFSET Int2F - MoveDown
         jne @@CannotRemove
        mov ax, es
        cmp ax, dx
         jne @@CannotRemove             ; Other TSR has Int 2F vector!

; OK to remove previous copy from RAM
; First, restore timer vector

        push ds
        mov dx,[word ptr ES:OldTimer-MoveDown]
        mov ds,[word ptr ES:OldTimer+2-MoveDown]
        mov ax,2508h
        int 21h

; Then, restore Int 2F vector

        mov dx,[word ptr ES:OldInt2F-MoveDown]
        mov ds,[word ptr ES:OldInt2F+2-MoveDown]
        mov ax,252Fh
        int 21h

        pop ds

; Next, release the memory segment
; ES -> to previos copy!

        mov ah,49h
        int 21h

        mov dx, OFFSET RemovedMsg
        mov ah,9
        int 21h

        mov ax,4C00h
        int 21h

@@CannotRemove:
        mov dx, OFFSET NotRemovedMsg
        mov ah,9
        int 21h

        mov ax,4C01h
        int 21h

ParseOption Endp

hour    dw ?
min     dw ?
sec     dw ?

DeTime Proc near
        mov ax,EXTENDED_CODE + (DELTATIME_CODE * 256)
        jmp short ParseTime
AtTime:
        mov ax,EXTENDED_CODE + (ATTIME_CODE * 256)
        jmp short ParseTime
TimeOut:
        mov ax,EXTENDED_CODE + (SETTIMEOUT_CODE * 256)
ParseTime:
        stosw                           ; Save marker for time

; FIX BUG found by davidgb. HOUR and Min MUST be initialized to ZERO!

        xor ax,ax
        mov [hour],ax
        mov [min],ax

; END OF bug-fix
        
        ; ** 3.30. Preset error msg as GetNumber jmps directly to        
        ; "Syntax" if it gets a bad input. Terje's 'efficient' but 
        ; hard to follow style. J.G.
        
        mov SynErrMsg, OFFSET BadTimeMsg
        mov BadNum, False
        mov BadRange, False
                                                
        mov al,[si]                     ; si -> start of number
        cmp al,'.'                      ; decimal point?
        jne @@Normal                    ; No, go with normal time
        inc si                          ; Else, skip '.', and get number
        mov bx,18                       ; as timer ticks, max 18.
        call GetNumber                  ; Note: Getnumber will NOT return
                                        ; on a bad value or range!!
        sub dx,dx                       ; Time comes back in bx.
        mov ax,dx                       ; Pass ticks in dx:ax, with dx=0.
        or  al,bl                       ; "or" in ticks, test for unwanted
        jnz @@SomeTicks                 ; zero ticks. Default 1 tick.
        inc al
@@SomeTicks:
        jmp @@SaveTicks

@@Normal:
        mov bx,59                       ; Max value. Note GetNumber
        call GetNumber                  ; will NOT return if bad value!
        cmp al,':'
         jne @@SaveSec
@@Mins:
        mov [min],bx
        mov bx,59
        call GetNumber
        cmp al,':'
         jne @@SaveSec

        xchg bx,[min]
        mov [hour],bx
        mov bx,59
        call GetNumber
        cmp al,':'
         jne @@SaveSec
BadTime:
        mov ErrLoc, si
        jmp Syntax

@@SaveSec:
        mov [sec],bx

; Now convert hour:min:sec into Timer ticks:
; Ticks= (hour*TicksPrHour) + (((min*60)+sec) * 34829 + 956) DIV 1913
; 34829 / 1913 is 18.206482, which is the closest possible result to
; the true value of 18.206493 Ticks/second, using only 16 bit mul and div.

        mov ax,(TicksPrHour - 65536)
        mul [hour]
        add dx,[hour]                   ; DX:AX = hour*TicksPrHour
        push ax                         ; Save DX:AX
        push dx                         ; --- " ---

        mov al,60
        mul [byte ptr min]
        add ax,[sec]                    ; AX has # of seconds

        mov dx,34829
        mul dx
        add ax,1913 Shr 1               ; Add 1913/2 to get automatic rounding
        adc dx,0                        ; of fractional timer ticks
        mov bx,ax
        mov ax,dx
        xor dx,dx
        mov cx,1913
        div cx
        xchg ax,bx
        div cx                          ; BX:AX = Ticks in (min*60+sec)

        pop dx
        pop cx                          ; DX:CX = Ticks in hours

        add ax,cx
        adc dx,bx                       ; DX:AX = Total Ticks
@@SaveTicks:                            ; Here direct if arg given in ticks
                                        ; i.e. +2t.  
        stosw                           ; Save Low word of count
        mov al,dl
        stosb                           ; Save high byte of count

         jmp ParseNextChar
DeTime Endp

PromptText:
        mov SynErrMsg, OFFSET BadPromptMsg
        mov StartItem, si
        mov ax,EXTENDED_CODE + (PROMPT_CODE * 256)
        stosw

;*** V.3.30 "Easy Prompt" - allows user to supply text only.
;*** Prompt/find variables stored in destination buffer (ES:DI): 
;    byte x, byte y, word slop, byte len, byte attrib
;    note user never supplies len, and attrib is optional.

        mov al,[si]                     ; check for immediate " or ' 
        cmp al,'"'
        je easy_prompt
        cmp al,"'"
        jne normal_prompt

easy_prompt:
        push ax                         ; save " or ' in al
        sub ax,ax
        stosw                           ; zero Prompt dx, dy bytes
        mov ax,PROMPTSLOP               ; get default slop, store in
        mov bp,ax                       ; bp as "easy" flag, and in
        stosw                           ; dest buffer es:di -> word slop
        pop ax                          ; now es:di -> byte len
        mov ah, NO_ATTR                 ; default (no) char attribute
        inc si                          ; ds:si -> 1st char in string
        jmp Text2                       ; skip to text scanning

normal_prompt:        
        mov bx,127
        call GetNumber
        cmp al,','
         jne BadFindParm
        mov al,bl                       ; Save X value
        stosb

        mov bx,60                       ; 0<y<=60
        call GetNumber
        cmp al,','
         jne BadFindParm
        mov al,bl
        stosb                           ; Save Y value

         jmp short Text1

;********** Error handler common to PromptText and FindText *******
;*** 3.30 Trying to clean this up so I can understand it...
;   Terje favors jumps over calls for speed/size, but it makes for
; difficult code to read/modify (IMHO)! J.Geist 1Sep92
;*** 4.00 Moved this error handler between proc's PrompText and FindText
; as it is common to both - in fact code starting at "Text1:" is common
; to both procs. Check ptr SynErrMsg to find 'caller'. It will point to
; BadPromptMsg or BadFindMsg. JG 24Oct92.  
;
BadFindParm:
        mov BadParm, True
        jmp short BadFind
BadFindVal:
        mov BadRange, True
        jmp short BadFind
BadFindString:
        mov BadString, True
BadFind:        
        mov ErrLoc, si
        jmp Syntax
;******************** End common error handler **********************

FindText proc near
        mov SynErrMsg, OFFSET BadFindMsg
        mov StartItem, si
        mov ax,EXTENDED_CODE + (FIND_CODE * 256) ; 255 + 3 -> flag for Find Text
        stosw
        mov bx,132                      ; 0<x<=132
        call GetNumber
        cmp al,','
         jne BadFindParm                ;'BadFind..' labels common to 
        sub bl,1                        ; PromptText and FindText. v.4.00
         jb BadFindVal                  ; 
        mov cx,bx                       ; Save X value

        mov bx,60                       ; 0<y<=60
        call GetNumber
        cmp al,','
         jne BadFindParm
        sub bl,1
         jb BadFindParm

        mov al,80
        mul bl
        add ax, cx
        shl ax, 1
        stosw                           ; Save X,Y as starting offset

;*** Starting at Text1:, code is shared by FindText and PromptText.
;    Thus, should check pointer SynErrMsg if need to know which
;    proc we 'came' from. v.4.00 
Text1:
        mov bx,(132*60)                 ; Get length to search in
        call GetNumber
        cmp al,','
         jne BadFindParm
        or bx,bx
         jz BadFindVal                  ; Count must be > 0

        mov ax,bx
        stosw                           ; Save buffer length

        mov bx,255
        cmp byte ptr [si],'"'
         je @@SkipAttr
        cmp byte ptr [si],"'"
         je @@SkipAttr

        call GetNumber
        cmp al,','
         jne BadFindParm


@@SkipAttr:
        sub bp,bp                       ; zap bp, flag for "easy prompt"
        mov ah,bl
        lodsb
        cmp al,'"'
         je @@1
        cmp al,"'"
         jne BadFindString
@@1:

; *** V. 3.30 straight to here (Text2:) on easy_prompt.
; ds:si -> 1st byte after " or ' in a string in source buffer
; es:di -> to attribute byte storage in dest buffer
; bp = PROMPTSLOP if Easy_prompt desired.
; ah = attribute, 255 means ignore attr.
; al = " or ' beginning the string. Result of last lodsb. (ds:si -1 )

Text2:                                  
        mov bx,di                       ; Save current pos for len
        stosw                           ; Store len (al) + attr (ah)
                                        ; Note len will be overwritten later
        mov ah,al                       ; save quote(s), string delimiters
        xor cx,cx
@@2:
        lodsb
        cmp al,EOF
         je  BadFindString
        cmp al,13
         je BadFindString
        cmp al,ah
         je @@3

        inc cx                          ; INC len
        stosb                           ; Save Text
        jmp @@2

@@3:
;*** Prompt/find vars: byte x, byte y, word slop, byte len, byte attrib        
        mov [ES:bx],cl                  ; Save actual length!
        cmp bp, PROMPTSLOP              ; Are we doing an "easy prompt" ?
        jnz @@Pdone                     ; no - leave.
                                        ; yes, stuff default prompt values
@@default_prompt:
        add cl, PROMPTADD               ; add to actual string length
        or word ptr [ES:bx-4], 0        ; double check "easy prompt"
        jnz @@Pdone
        mov [ES:bx-4], cl               ; store in [cursor horizontal - x]
@@Pdone:        
        jmp ParseNextChar               ; jump (shudder) to parser
FindText endp

GetNumber proc near
; input: SI -> first char to convert, BX = max value
; Output: BX = number if no error. 
;         Jumps directly to Syntax error handler on error (hmmm)
;         3.30 sets BadNum, BadRange for invalid number or range.
        
        mov  BadNum, False              ; Clear bad value & range flags
        mov  BadRange, False            ;
        mov  ErrLoc, si                 ; Save source pos. in case of err.
        push cx                         ; Use as temp buffer
        push dx                         ; For mul
        push di                         ; For sign flag

        sub cx,cx
        mov ah,ch
        mov di,cx                       ; Zero DI -> Positive

        cmp byte ptr [si],'-'
         jne @@GetLoop
        dec di
        inc si

@@GetLoop:
        lodsb
        cmp al,' '
         jbe @@GetEnd
        cmp al,':'
         je @@GetEnd
        cmp al,','
         je @@GetEnd

        sub al,'0'
         jb @@BadNumber
        cmp al,9
         ja @@BadNumber

; Valid decimal digit!                  ; These comments added in 3.30
        xchg ax,cx                      ; swap new#(ax) with old#(cx) 
        mov dx,10                       ; want to mul old number by 10.
        mul dx                          ; old#(ax) * 10(dx) -> ax
        add cx,ax                       ; now add in new#, keep in cx.
         jmp @@GetLoop                  ; Go check for more digits, etc.
@@GetEnd:
        cmp al,EOF
         jne @@1
        dec si                          ; Prepare to reload AL
@@1:
        cmp cx,bx                       ; Valid value?
         ja @@BadRange                 ; bad if new#(cx) > max#(bx)
        mov bx,cx                       ; 

        or di,di
         jz @@done

        neg bx                          ; return -BX

@@done:
        pop di
        pop dx
        pop cx
        ret
@@BadNumber:
        mov BadNum, True                ; Bad number implies bad range
@@BadRange:                             ; so chk it 1st, then range,
        mov BadRange, True              ; in error display routine. v3.30
        mov ErrLoc, si                  ; Save in ErrLoc pointer.
        jmp Syntax                      ; saves space, but ?
GetNumber endp

SaveChar proc near
; AL, AH = char, scan to save in StuffBuffer

        or al,al
         je @@Save2
        cmp al,224
         je @@Save2

        cmp al,254
         jae @@Save3
        cmp ah,2                        ; Scan for normal chars
         jne @@Save3

        mov ah,14
        cmp al,8
         je @@Save3
        mov ah,15
        cmp al,9
         je @@Save3
        mov ah,28
        cmp al,13
         je @@Save3
        mov ah,1
        cmp al,27
         je @@Save3

; Normal character, store just the char itself

        stosb
        ret

@@Save2:
        stosw
        ret

@@Save3:
        mov byte ptr [es:di],254
        inc di
        stosw
        ret
SaveChar endp

MaxTokenSize = 8                        ; V.4.0. 9 vs 8 for {IfSuccess}
                                        ; leaving as {IfSucc} for now.

CurToken   db MaxTokenSize dup (0)

TokenTable      label byte

T_S     struc
tname   db      MaxTokenSize dup (0)
tchr    db      ?
tscn    db      ?
        ends

        T_S     <"ESC",27,1>

TokenRecSize    = $ - offset TokenTable

        T_S     <"aEsc",0,1>

        T_S     <"^@",0,3>
        T_S     <"^A",1,30>
        T_S     <"^B",2,48>
        T_S     <"^C",3,46>
        T_S     <"^D",4,32>
        T_S     <"^E",5,18>
        T_S     <"^F",6,33>
        T_S     <"^G",7,34>
        T_S     <"^H",8,35>
        T_S     <"^I",9,23>
        T_S     <"^J",10,36>
        T_S     <"^K",11,37>
        T_S     <"^L",12,38>
        T_S     <"^M",13,50>
        T_S     <"^N",14,49>
        T_S     <"^O",15,24>
        T_S     <"^P",16,25>
        T_S     <"^Q",17,16>
        T_S     <"^R",18,19>
        T_S     <"^S",19,31>
        T_S     <"^T",20,20>
        T_S     <"^U",21,22>
        T_S     <"^V",22,47>
        T_S     <"^W",23,17>
        T_S     <"^X",24,45>
        T_S     <"^Y",25,21>
        T_S     <"^Z",26,44>
        T_S     <"^[",27,26>
        T_S     <"^\",28,43>
        T_S     <"^]",29,27>
        T_S     <"^^",30,7>
        T_S     <"^_",31,12>

        T_S     <"NUL",0,3>
        T_S     <"SOH",1,30>
        T_S     <"STX",2,48>
        T_S     <"ETX",3,46>
        T_S     <"EOT",4,32>
        T_S     <"ENQ",5,18>
        T_S     <"ACK",6,33>
        T_S     <"BEL",7,34>
;        T_S     <"BS",8,35>            ; Defined as BS key
        T_S     <"HT",9,23>             ; HT = ^H = TAB
        T_S     <"LF",10,36>
        T_S     <"VT",11,37>
        T_S     <"FF",12,38>
;        T_S     <"CR",13,50>           ;  --"--     CR
        T_S     <"SO",14,49>
        T_S     <"SI",15,24>
        T_S     <"DLE",16,25>
        T_S     <"DC1",17,16>
        T_S     <"DC2",18,19>
        T_S     <"DC3",19,31>
        T_S     <"DC4",20,20>
        T_S     <"NAK",21,22>
        T_S     <"SYN",22,47>
        T_S     <"ETB",23,17>
        T_S     <"CAN",24,45>
        T_S     <"EM",25,21>
        T_S     <"SUB",26,44>
;        T_S     <"ESC",27,26>          ;  --"--     ESC
        T_S     <"FS",28,43>
        T_S     <"GS",29,27>
        T_S     <"RS",30,7>
        T_S     <"US",31,12>

FirstChar       label byte              ; Use to translate characters into
                                        ; char:scan pairs

        T_S     <" ",32,57>
        T_S     <"!",33,2>
        T_S     <'"',34,40>
        T_S     <"#",35,4>
        T_S     <"$",36,5>
        T_S     <"%",37,6>
        T_S     <"&",38,8>
        T_S     <"'",39,40>
        T_S     <"(",40,10>
        T_S     <")",41,11>
        T_S     <"*",42,9>
        T_S     <"+",43,13>
        T_S     <",",44,51>
        T_S     <"-",45,12>
        T_S     <".",46,52>
        T_S     <"/",47,53>

        T_S     <"0",48,11>
        T_S     <"1",49,2>
        T_S     <"2",50,3>
        T_S     <"3",51,4>
        T_S     <"4",52,5>
        T_S     <"5",53,6>
        T_S     <"6",54,7>
        T_S     <"7",55,8>
        T_S     <"8",56,9>
        T_S     <"9",57,10>
        T_S     <":",58,39>
        T_S     <";",59,39>
        T_S     <"<",60,51>
        T_S     <"=",61,13>
        T_S     <">",62,52>
        T_S     <"?",63,53>

        T_S     <"@",'@',3>
        T_S     <"A",'A',30>
        T_S     <"B",'B',48>
        T_S     <"C",'C',46>
        T_S     <"D",'D',32>
        T_S     <"E",'E',18>
        T_S     <"F",'F',33>
        T_S     <"G",'G',34>
        T_S     <"H",'H',35>
        T_S     <"I",'I',23>
        T_S     <"J",'J',36>
        T_S     <"K",'K',37>
        T_S     <"L",'L',38>
        T_S     <"M",'M',50>
        T_S     <"N",'N',49>
        T_S     <"O",'O',24>
        T_S     <"P",'P',25>
        T_S     <"Q",'Q',16>
        T_S     <"R",'R',19>
        T_S     <"S",'S',31>
        T_S     <"T",'T',20>
        T_S     <"U",'U',22>
        T_S     <"V",'V',47>
        T_S     <"W",'W',17>
        T_S     <"X",'X',45>
        T_S     <"Y",'Y',21>
        T_S     <"Z",'Z',44>
        T_S     <"[",'[',26>
        T_S     <"\",'\',43>
        T_S     <"]",']',27>
        T_S     <"^",'^',7>
        T_S     <"_",'_',12>

        T_S     <"`",'`',41>
        T_S     <"a",'a',30>
        T_S     <"b",'b',48>
        T_S     <"c",'c',46>
        T_S     <"d",'d',32>
        T_S     <"e",'e',18>
        T_S     <"f",'f',33>
        T_S     <"g",'g',34>
        T_S     <"h",'h',35>
        T_S     <"i",'i',23>
        T_S     <"j",'j',36>
        T_S     <"k",'k',37>
        T_S     <"l",'l',38>
        T_S     <"m",'m',50>
        T_S     <"n",'n',49>
        T_S     <"o",'o',24>
        T_S     <"p",'p',25>
        T_S     <"q",'q',16>
        T_S     <"r",'r',19>
        T_S     <"s",'s',31>
        T_S     <"t",'t',20>
        T_S     <"u",'u',22>
        T_S     <"v",'v',47>
        T_S     <"w",'w',17>
        T_S     <"x",'x',45>
        T_S     <"y",'y',21>
        T_S     <"z",'z',44>
        T_S     <"{",'{',26>
        T_S     <"|",'|',43>
        T_S     <"}",'}',27>
        T_S     <"~",'~',7>

        T_S     <"‘",'‘',40>
        T_S     <"›",'›',39>
        T_S     <"†",'†',26>
        T_S     <"’",'’',40>
        T_S     <"",'',39>
        T_S     <"",'',26>

LastChar        label byte

        T_S     <"a1",0,120>
        T_S     <"a2",0,121>
        T_S     <"a3",0,122>
        T_S     <"a4",0,123>
        T_S     <"a5",0,124>
        T_S     <"a6",0,125>
        T_S     <"a7",0,126>
        T_S     <"a8",0,127>
        T_S     <"a9",0,128>
        T_S     <"a0",0,129>
        T_S     <"a-",0,130>
        T_S     <"a=",0,131>

        T_S     <"BS",8,14>
        T_S     <"aBS",0,14>
        T_S     <"^BS",127,14>

        T_S     <"Tab",9,15>
        T_S     <"sTab",0,15>
        T_S     <"^Tab",0,148>

        T_S     <"CR",13,28>
        T_S     <"^CR",10,28>
        T_S     <"aCR",0,28>

        T_S     <"aQ",0,16>
        T_S     <"aW",0,17>
        T_S     <"aE",0,18>
        T_S     <"aR",0,19>
        T_S     <"aT",0,20>
        T_S     <"aY",0,21>
        T_S     <"aU",0,22>
        T_S     <"aI",0,23>
        T_S     <"aO",0,24>
        T_S     <"aP",0,25>
        T_S     <"a[",0,26>
        T_S     <"a]",0,27>

        T_S     <"aA",0,30>
        T_S     <"aS",0,31>
        T_S     <"aD",0,32>
        T_S     <"aF",0,33>
        T_S     <"aG",0,34>
        T_S     <"aH",0,35>
        T_S     <"aJ",0,36>
        T_S     <"aK",0,37>
        T_S     <"aL",0,38>
        T_S     <"a;",0,39>
        T_S     <"a'",0,40>
        T_S     <"a`",0,41>

        T_S     <"a\",0,43>
        T_S     <"aZ",0,44>
        T_S     <"aX",0,45>
        T_S     <"aC",0,46>
        T_S     <"aV",0,47>
        T_S     <"aB",0,48>
        T_S     <"aN",0,49>
        T_S     <"aM",0,50>
        T_S     <"a,",0,51>
        T_S     <"a.",0,52>
        T_S     <"a/",0,53>

        T_S     <"a*",0,55>

        T_S     <"F1",0,59>
        T_S     <"F2",0,60>
        T_S     <"F3",0,61>
        T_S     <"F4",0,62>
        T_S     <"F5",0,63>
        T_S     <"F6",0,64>
        T_S     <"F7",0,65>
        T_S     <"F8",0,66>
        T_S     <"F9",0,67>
        T_S     <"F10",0,68>

        T_S     <"n/",'/',224>
        T_S     <"n*",'*',55>
        T_S     <"n7",'7',74>
        T_S     <"n8",'8',72>
        T_S     <"n9",'9',73>
        T_S     <"n-",'-',74>
        T_S     <"n4",'4',75>
        T_S     <"n5",'5',76>
        T_S     <"n6",'6',77>
        T_S     <"n+",'+',78>
        T_S     <"n1",'1',79>
        T_S     <"n2",'2',80>
        T_S     <"n3",'3',81>
        T_S     <"n0",'0',82>
        T_S     <"n.",'.',83>
        T_S     <"Enter",13,224>

        T_S     <"Home",0,71>
        T_S     <"Up"  ,0,72>
        T_S     <"PgUp",0,73>
        T_S     <"Left",0,75>
        T_S     <"Right",0,77>
        T_S     <"End" ,0,79>
        T_S     <"Down",0,80>
        T_S     <"PgDn",0,81>
        T_S     <"Ins" ,0,82>
        T_S     <"Del" ,0,83>

        T_S     <"^n/",0,149>
        T_S     <"^n*",0,150>
        T_S     <"^Home",0,119>
        T_S     <"^Up"  ,0,141>
        T_S     <"^PgUp",0,132>
        T_S     <"^n-",0,142>
        T_S     <"^Left",0,115>
        T_S     <"^n5",0,143>
        T_S     <"^Right",0,116>
        T_S     <"^n+",0,144>
        T_S     <"^End" ,0,117>
        T_S     <"^Down",0,145>
        T_S     <"^PgDn",0,118>
        T_S     <"^Ins" ,0,146>
        T_S     <"^Del" ,0,147>
        T_S     <"^Enter",10,224>

        T_S     <"an/",0,164>
        T_S     <"an*",0,55>
        T_S     <"an-",0,74>
        T_S     <"an+",0,78>
        T_S     <"aEnter",10,224>

        T_S     <"eHome",224,71>
        T_S     <"eUp"  ,224,72>
        T_S     <"ePgUp",224,73>
        T_S     <"eLeft",224,75>
        T_S     <"eRight",224,77>
        T_S     <"eEnd" ,224,79>
        T_S     <"eDown",224,80>
        T_S     <"ePgDn",224,81>
        T_S     <"eIns" ,224,82>
        T_S     <"eDel" ,224,83>

        T_S     <"^eHome",224,119>
        T_S     <"^eUp"  ,224,141>
        T_S     <"^ePgUp",224,132>
        T_S     <"^eLeft",224,115>
        T_S     <"^eRight",224,116>
        T_S     <"^eEnd" ,224,117>
        T_S     <"^eDown",224,145>
        T_S     <"^ePgDn",224,118>
        T_S     <"^eIns" ,224,146>
        T_S     <"^eDel" ,224,147>

        T_S     <"aeHome",0,151>
        T_S     <"aeUp"  ,0,152>
        T_S     <"aePgUp",0,153>
        T_S     <"aeLeft",0,155>
        T_S     <"aeRight",0,157>
        T_S     <"aeEnd" ,0,159>
        T_S     <"aeDown",0,160>
        T_S     <"aePgDn",0,161>
        T_S     <"aeIns" ,0,162>
        T_S     <"aeDel" ,0,163>

        T_S     <"sF1",0,84>
        T_S     <"sF2",0,85>
        T_S     <"sF3",0,86>
        T_S     <"sF4",0,87>
        T_S     <"sF5",0,88>
        T_S     <"sF6",0,89>
        T_S     <"sF7",0,90>
        T_S     <"sF8",0,91>
        T_S     <"sF9",0,92>
        T_S     <"sF10",0,93>

        T_S     <"^F1",0,94>
        T_S     <"^F2",0,95>
        T_S     <"^F3",0,96>
        T_S     <"^F4",0,97>
        T_S     <"^F5",0,98>
        T_S     <"^F6",0,99>
        T_S     <"^F7",0,100>
        T_S     <"^F8",0,101>
        T_S     <"^F9",0,102>
        T_S     <"^F10",0,103>

        T_S     <"aF1",0,104>
        T_S     <"aF2",0,105>
        T_S     <"aF3",0,106>
        T_S     <"aF4",0,107>
        T_S     <"aF5",0,108>
        T_S     <"aF6",0,109>
        T_S     <"aF7",0,110>
        T_S     <"aF8",0,111>
        T_S     <"aF9",0,112>
        T_S     <"aF10",0,113>

        T_S     <"^PrtScrn",0,114>

        T_S     <"F11",0,133>
        T_S     <"F12",0,134>
        T_S     <"sF11",0,135>
        T_S     <"sF12",0,136>
        T_S     <"^F11",0,137>
        T_S     <"^F12",0,138>
        T_S     <"aF11",0,139>
        T_S     <"aF12",0,140>

; Special functions with full names:

        T_S     <"PrtScrn",255,PRTSCRN_CODE>
        T_S     <"Boot"   ,255,REBOOT_CODE>
        T_S     <"^aDel"  ,255,REBOOT_CODE>     ; Ctrl-Alt-Del is an alias
                                                ; for Boot!
        T_S     <"AtTime" ,255,ATTIME_CODE>
        T_S     <"Wait"   ,255,DELTATIME_CODE>
        T_S     <"Find"   ,255,FIND_CODE>
        T_S     <"Prompt" ,255,PROMPT_CODE>
        T_S     <"^Break" ,255,BREAK_CODE>
        T_S     <"TimeOut",255,SETTIMEOUT_CODE> ; V.3.30 for Prompt, Find
        T_S     <"IfSucc" ,255,IFSUCCESS_CODE>  ; V.4.00 test of above        
        T_S     <"IfTrue" ,255,IFSUCCESS_CODE>  ; allow If Succ, True,        
        T_S     <"IfT"    ,255,IFSUCCESS_CODE>  ; and T.        
        T_S     <"IfFail" ,255,IFFAIL_CODE>     ;                
        T_S     <"IfFalse",255,IFFAIL_CODE>     ;                
        T_S     <"IfF"    ,255,IFFAIL_CODE>     ;                
        T_S     <"Else"   ,255,ELSE_CODE>       ; " else for IfSuccess
        T_S     <"Endif"  ,255,ENDIF_CODE>      ; " end IfSuccess & Else
        T_S     <"Stop"   ,255,STOP_CODE>       ; For aborting script
EndToken        label byte

GetToken        proc                    ; AL = '{', SI -> next char

        push    cx di

        mov     ah,'}'                  ; Assume '{ for start of token
        cmp     al,'{'
         je     @@l1
        mov     ah,']'                  ; No, so it must be '['
@@l1:
        mov     di, offset CurToken
        mov     cx, MaxTokenSize
        lodsb                           ; Must be at least one char,
@@next:                                 ; so {{} is OK!
        stosb
        dec     cx
         jz     @@full
        lodsb
        cmp     al,' '
         jbe    @@MissingBrace
        cmp     al,ah
         jne    @@next

        mov     al,0
        rep     stosb
@@full:

        cmp     CurToken[1],0           ; Length = 1?
         je     @@done                  ; Yes, so leave alone!

        mov     di, offset CurToken
        mov     cx, MaxTokenSize
@@load:
        mov     al,[di]
        cmp     al,'a'
         jb     @@upper
        cmp     al,'z'
         ja     @@upper
        sub     al,'a'-'A'
        mov     [di],al
@@upper:
        inc     di
         loop   @@load
@@done:
        pop     di cx
        ret

@@MissingBrace:
        jmp     Syntax
GetToken        endp

TokenUpper      db 0

FindToken proc near             ; bx => token
; Return CLC (and AX) if found, STC if not found

        push    cx dx si di

        cmp     [TokenUpper],0
         jne    @@TokenUpper
        call    UpcaseToken             ; Converts token table to uppercase!
        mov     [TokenUpper],1

@@TokenUpper:
        mov     dx, offset TokenTable - TokenRecSize

@@testtoken:
        add     dx, TokenRecSize
        cmp     dx, offset EndToken
        cmc
         jc     @@done

        mov     si, offset CurToken
        mov     di,dx
        mov     cx, MaxTokenSize SHR 1
   repe cmpsw
         jne     @@TestToken

        mov     ax,[di]
        clc
@@done:
        pop     di si dx cx
        ret
FindToken       endp

UpcaseToken     proc
        push    cx dx di

        mov     dx, offset TokenTable

@@testtoken:
        mov     di,dx
        cmp     byte ptr [di+1],0       ; Token length = 1?
         je     @@end                   ; Yes, so skip this!

        mov     cx, MaxTokenSize

@@upcase:
        mov     al,[di]
        or      al,al
         jz     @@end
        cmp     al,'a'
         jb     @@upper
        cmp     al,'z'
         ja     @@upper
        sub     al,'a'-'A'
@@upper:
        stosb
         loop   @@upcase
@@end:
        add     dx, TokenRecSize
        cmp     dx, offset EndToken
         jb     @@testtoken

@@done:
        pop     di dx cx
        ret
UpcaseToken     endp

ListKeys        proc    near
        push    bx cx dx si di

        mov     si, offset TokenTable

@@print3:
        mov     di, 3

@@testtoken:
        cmp     si, offset EndToken
         jae    @@done

        mov     bx,'[' + ']' * 256
        cmp     byte ptr [si],'{'
         je     @@UseBrackets
        cmp     byte ptr [si],'}'
         je     @@UseBrackets

        mov     bx,'{' + '}' * 256      ; Use '{}' pair for all others

@@UseBrackets:
        mov     dl,bl
        mov     ah,2
        int     21h

        mov     cx, MaxTokenSize
@@nextchar:
        mov     al,[si]
        or      al,al
         jz     @@zero
        inc     si
        mov     dl,al
        mov     ah,2
        int     21h
         loop   @@nextchar
@@zero:
        mov     dl,bh
        mov     ah,2
        int     21h

        add     si,cx
        call    Space

        lodsb                   ; Character value
        xor     ah,ah
        mov     cx,3
        call    PrintAX
        mov     dl,':'
        mov     ah,2
        int     21h
        lodsb                   ; Character value
        xor     ah,ah
        xor     cx,cx
        call    PrintAX
        dec     di
         jz     @@Eoln

        add     cx,8
        call    Space
         jmp    @@testtoken
@@Eoln:
        mov     dx, offset CRLF
        mov     ah,9
        int     21h
         jmp    @@print3
@@done:
        pop     di si dx cx bx

        mov     ax,4C00h
        int     21h

        ret
ListKeys        endp

PrintAX proc    near
        push    dx si di

        mov     si,ax
        mov     bx,10
        mov     di,cx
        xor     cx,cx
@@next:
        mov     ax,si
        xor     dx,dx
        div     bx
        mov     si,ax
        mov     ah,2
        add     dl,'0'
        push    dx
        inc     cx
        or      si,si
         jnz    @@next

        sub     di,cx
         jbe    @@popDL

        xchg    cx,di
        call    Space
        xchg    cx,di
@@popDL:
        pop     dx
        mov     ah,2
        int     21h
         loop   @@popDL

        mov     cx,di
        pop     di si dx
        ret
PrintAX endp

Space   proc

         jcxz   @@done
@@space:
        mov     dl,' '
        mov     ah,2
        int     21h
         loop   @@space
@@done:
        ret

Space   endp

ProgramEnd label byte

CODE ENDS
        END start

