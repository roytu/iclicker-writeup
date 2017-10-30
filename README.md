
Documentation Note
======================
This document was written several years after this project ended.  We are reconstructing what we did based on the patched code itself, and scraps of notes here and there.  Hence, some of it might be misleading, or straight wrong.  But we tried.  We really did!

Feel free to submit pull requests.

Overview
==========
The original iClicker uses an ATMega8U2 chip as a microcontroller, which talks to a transceiver chip to transmit/receive votes.  The board has a 6-pin SPI interface (which one solders a header to) to talk to the chip.

The chip has two relevant non-volatile memory sections:

Flash: stores the firmware
EEPROM: stores the unique iClicker ID and some copyright information

SPI Header
=============
TODO describe 6-pin SPI pinout

Communication (Hardware)
===========================
To communicate to the AVR chip, we need an AVR programmer.  Commercial USB-to-SPI AVR programmers exist and are cheap, but fortunately it is possible to turn any Arduino into a programmer (see https://www.arduino.cc/en/Tutorial/ArduinoISP ).  The Arduino shows up as a device (/dev/tty* on Unix systems) and acts as an interface between our computer and the iClicker chip.

After wiring it up according to the link above, we can communicate with the ATMega8U2 using avrdude:

    avrdude -v -P /dev/ttyACM0 -c avrisp -p m8 -b 19200 -U flash:w:new_flash12.bin:r

where the flags are:

-v: verbose output
-P <device>: device handle to the SPI programmer
-c avrisp: programmer id (our Arduino)
-p m8: type of the microcontroller we are programming (m8 for ATMega8U2)
-b 19200: baud rate (19200 seems to work reliably)
-U <memtype:op:filename:filefmt>: upload options.  See man avrdude for details

Reading the program memory
============================
For the rest of the documentation, we assume our Arduino device handle is /dev/ttyACM0.

We can read the firmware with:

    avrdude -v -P /dev/ttyACM0 -c avrisp -p m8 -b 19200 -U flash:r:<filename>.bin:r

which will save the firmware in some raw format.

At this point I'm sure there's some canonical way to disassemble the binary but we really just use this online disassembler ( https://www.onlinedisassembler.com/odaweb ) with format avr:4, disassemble the full file, and copy/paste the output.  The avid reader should figure out how to do it with avr-objdump, and submit a pull request.

The result looks something like:

     .data:0x00000000    13c0    rjmp .+38 ; 0x00000028  
    .data:0x00000002    e9c1    rjmp .+978 ; 0x000003d6 
    .data:0x00000004    fdcf    rjmp .-6 ; 0x00000000   
    .data:0x00000006    fccf    rjmp .-8 ; 0x00000000   
    .data:0x00000008    fbcf    rjmp .-10 ; 0x00000000  
    .data:0x0000000a    facf    rjmp .-12 ; 0x00000000  
    .data:0x0000000c    f9cf    rjmp .-14 ; 0x00000000  
    ...

Patching the firmware
========================
When a vote occurs normally, the iClicker reads the EEPROM for its ID and transmits it along with the chosen letter to the base station.  Upon success, the base station sends a signal to the transceiver, which presumably triggers an interrupt on the iClicker.  This interrupt tells the iClicker of the success (the green LED blinks), and the iClicker stops sending votes.  If the signal is never received, the iClicker tries 4 times before giving up (the red LED blinks, signalling failure).

Our objectives for the patch are as follows:
    1. Change 4 to a really large number, so the iClicker makes many attempts.
    2. Cut the interrupt signal that stops the iClicker from voting.
    3. Change the delay between votes to something really small, so it votes as fast as possible.
    4. Perturb the EEPROM ID so each vote looks like it's coming from a unique iClicker.

Interrupt (Objective #2)
==========================
For AVR chips, the data space from 0x00 to 0x38 stores the interrupt vector table, which tells the program where to jump to when certain interrupts trigger.  See section 11.2 of http://www.atmel.com/images/doc7799.pdf for the ATMega8U2 table.  By checking the traces of the iClicker PCB we see that the transceiver is connected to INT0 on the chip, suggesting that INT0 is triggered when data is received.  INT0's vector is stored at 0x02 of flash memory, where we see this line:

    .data:0x00000002    e9c1    rjmp .+978 ; 0x000003d6 

At 0x03d6, we see the following code:

    .data:0x000003d6    ea93    st -Y, r30                  Store r30 in y-1  
    .data:0x000003d8    e1e0    ldi r30, 0x01 ; 1           Load 1 into r30
    .data:0x000003da    5e2e    mov r5, r30                 Load r30 into r5
    .data:0x000003dc    e991    ld r30, Y+                  Load y+1 into r30
    .data:0x000003de    1895    reti                        -Return from interrupt call-

This code stores the number 1 into register r5 and returns (and does some stuff with the Y register).  By searching for r5 in the code, we see that r5 is strictly boolean; the only instructions that write to r5 are line 0x03da and several eor r5, r5 instructions which clear r5.  My assumption is that this tells the iClicker that a packet has arrived from the transceiver and should be handled.  But we don't want our iClicker to know that our vote attempts are successful (objective #2 above), so we nop this line.

    .data:0x000003d6    ea93    st -Y, r30                  Store r30 in y-1  
    .data:0x000003d8    e1e0    ldi r30, 0x01 ; 1           Load 1 into r30
    .data:0x000003da    0000    nop
    .data:0x000003dc    e991    ld r30, Y+                  Load y+1 into r30
    .data:0x000003de    1895    reti                        -Return from interrupt call-

Scrambling the iClicker ID (Objective #4)
============================================
I don't remember how we figured this out but somehow we found the point where the actual pressed button press is read, at address 0x0522:

    .data:0x00000522    e3b3    in r30, 0x13 ; 19          Save GPIO input to r30
    .data:0x00000524    ef73    andi r30, 0x3F ; 63 
    .data:0x00000526    afe3    ldi r26, 0x3F ; 63  
    .data:0x00000528    ea27    eor r30, r26    
    .data:0x0000052a    0e2f    mov r16, r30    
    .data:0x0000052c    e0917a01    lds r30, 0x017A        Save r30 to 0x017A
    .data:0x00000530    e030    cpi r30, 0x00 ; 0   
    .data:0x00000532    39f1    breq .+78 ; 0x00000582  
    .data:0x00000534    0130    cpi r16, 0x01 ; 1   

We see the code read some GPIO input and do some logic, eventually storing it in memory location 0x017A.  Here is a really opportune place to scramble the iClicker ID, because we expect that right afterwards will be some code reading the ID from the stack.  At some point, we figured that the three iClicker ID was stored at 0x018F - 0x0191, so we wrote some code to scramble it before reading the button, placing it in the blank memory at the very end of flash memory:

    ....
    .data:0x00001122    ffff    .word 0xffff ; ???? 
    .data:0x00001124    ffff    .word 0xffff ; ???? 
    .data:0x00001126    e0918f01    lds r30, 0x018F ; Mix up all the values a little
    .data:0x00001128    e395    inc r30             ; First Byte
    .data:0x0000112a    e0938f01    sts 0x018F, r30 
    .data:0x0000112c    e0919001    lds r30, 0x0190 
    .data:0x0000112e    ea95    dec r30             ; Second Byte
    .data:0x00001130    e0939001    sts 0x0190, r30 
    .data:0x00001132    e0919101    lds r30, 0x0191 
    .data:0x00001134    e395    inc r30             ; Third Byte
    .data:0x00001136    e0939101    sts 0x0191, r30 
    .data:0x00001138    e3b3    in r30, 0x13        ; Actually read the button
    .data:0x0000113a    0895    ret

and then we modified the instruction at 0x0522 to call this:

    .data:0x00000522    01d6    rcall .+3074 ;        jump to 0x1126 

So now, every time the vote is sent out, each byte of the ID is incremented by one.  Strangely, when using this code on our test base station, the IDs don't increment but become seemingly pseudorandom, so probably this code is a little broken but anyway it gets the job done.

Decreasing the Vote Delay and Voting Many Times (Objectives #1 and #3)
==========================================================================
I don't know how we did this, it's been too long and our documentation sucks.  Here are the remaining lines that were changed according to a diff between the original and final versions:

    from:
    .data:0x0000023a    a330    cpi r26, 0x03 ; 3 
    to:
    .data:0x0000023a    af3f    cpi r26, 0xFF ; 255
    
    from:
    .data:0x000004a8    19f4    brne .+6 ; 0x000004b0   
    to:
    .data:0x000004a8    0000    nop
    
    from:
    .data:0x00000616    ebe4    ldi r30, 0x4B ; 75  
    to:
    .data:0x00000616    e2e0    ldi r30, 0x2  ; 2  
    
    from:
    .data:0x0000063a    e4e6    ldi r30, 0x64 ; 100 
    to:
    .data:0x0000063a    e2e0    ldi r30, 0x02 ; 2

    from:
    .data:0x00000f0a    e3e6    ldi r30, 0x63 ; 99  
    to:
    .data:0x00000f0a    e0ed    ldi r30, 0xD0 ; 208

The patched line on 0x0f0a in particular is suspiciously labeled "Overclock Code," and probably speeds up the delay between votes.  Timer interrupts are triggered by byte overflow in AVR -- that is, an internal timer increments steadily and triggers once it goes past 255.  So changing 99 to a higher number, like 208, would decrease the delay by nearly 1/3rd ((255 - 208) / (255 - 99)).

It's possible some of those changes above were inconsequential.

Uploading the firmware
========================
To upload our patched file we convert the disassembly back to raw format and reupload with avrdude:

    egrep -o "    [0-9a-f]{4,8}    " patched_code | egrep -o "[0-9a-f]{4,8}" | sed ':a;N;$!ba;s/\n//g' | xxd -r -p > result.bin
    avrdude -v -V -P /dev/ttyACM0 -c avrisp -p m8 -b 19200 -U flash:w:result.bin:r

This effectively selects the relevant assembly bytes in each line of the disassembler, e.g. converts:

    .data:0x00000000    13c0    rjmp .+38 ; 0x00000028  
    .data:0x00000002    e9c1    rjmp .+978 ; 0x000003d6 
    .data:0x00000004    fdcf    rjmp .-6 ; 0x00000000   
    .data:0x00000006    fccf    rjmp .-8 ; 0x00000000   
    .data:0x00000008    fbcf    rjmp .-10 ; 0x00000000  
    .data:0x0000000a    facf    rjmp .-12 ; 0x00000000 
    ...

to

    13c0e9c1fdcffccffbcffacf
    ...

and pipes the result to xxd -r which reassembles the bytes into an AVR binary file.  The avrdude line then re-uploads the binary to flash.

If everything goes well, the iClicker should now vote indefinitely!

References
============
http://www.atmel.com/images/doc7799.pdf
