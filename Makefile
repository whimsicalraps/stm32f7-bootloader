TARGET=boot
EXECUTABLE=boot.elf

CUBE=../STM32_Cube_F7/Drivers
HALS=$(CUBE)/STM32F7xx_HAL_Driver/Src
WRLIB=../../wrLib
WRDSP=../../wrDsp
PRJ_DIR=wslash-bootloader

CC=arm-none-eabi-gcc
CXX= arm-none-eabi-g++
LD=arm-none-eabi-gcc
AR=arm-none-eabi-ar
AS=arm-none-eabi-as
CP=arm-none-eabi-objcopy
OBJDUMP=arm-none-eabi-objdump

# BIN=$(CP) -O ihex 
BIN = $(TARGET).bin

DEFS = -DUSE_STDPERIPH_DRIVER -DSTM32F7XX -DARM_MATH_CM7 -DHSE_VALUE=8000000
STARTUP = $(CUBE)/CMSIS/Device/ST/STM32F7xx/Source/Templates/gcc/startup_stm32f765xx.s

# MCFLAGS = -march=armv7e-m -mthumb 
MCFLAGS = -mthumb -march=armv7e-m -mfloat-abi=hard -mfpu=fpv4-sp-d16

STM32_INCLUDES = \
	-I$(WRLIB)/ \
	-I$(WRDSP)/ \
	-I$(CUBE)/CMSIS/Device/ST/STM32F7xx/Include/ \
	-I$(CUBE)/CMSIS/Include/ \
	-I$(CUBE)/STM32F7xx_HAL_Driver/Inc/ \
	-I../stm-audio-bootloader/fsk/ \
	-I../stmlib/system/ \
	-I$(CUBE)/BSP/STM32F769I-Discovery/ \

OPTIMIZE       = -Os

CFLAGS += $(MCFLAGS)
CFLAGS += $(OPTIMIZE)
CFLAGS += $(DEFS) -I. -I./ $(STM32_INCLUDES)
CFLAGS += -fsingle-precision-constant -Wdouble-promotion

CPPFLAGS = $(CFLAGS) -fno-exceptions

C99 = -std=c99

R ?= 0
ifeq ($(R), 1)
    CFLAGS += -DRELEASE
else
    CFLAGS += -DDEBUG
endif

LDFLAGS = -Wl,-T,stm32_boot.ld
LIBS = -lm -lc -lnosys

SRC = stm32f7xx_it.c \
	system_stm32f7xx.c \
	stm32f7xx_hal_msp.c \
	$(HALS)/stm32f7xx_hal.c \
	$(HALS)/stm32f7xx_hal_cortex.c \
	$(HALS)/stm32f7xx_hal_rcc.c \
	$(HALS)/stm32f7xx_hal_rcc_ex.c \
	$(HALS)/stm32f7xx_hal_flash.c \
	$(HALS)/stm32f7xx_hal_flash_ex.c \
	$(HALS)/stm32f7xx_hal_gpio.c \
	$(HALS)/stm32f7xx_hal_dma.c \
	$(HALS)/stm32f7xx_hal_dma2d.c \
	$(HALS)/stm32f7xx_hal_pwr.c \
	$(HALS)/stm32f7xx_hal_pwr_ex.c \
	$(HALS)/stm32f7xx_hal_sai.c \
	$(HALS)/stm32f7xx_hal_usart.c \
	$(wildcard lib/*.c) \
	$(WRLIB)/str_buffer.c \
	$(WRLIB)/wrMath.c \
	$(WRDSP)/wrOscSine.c \
	$(WRDSP)/wrLpGate.c \


OBJDIR = .
OBJS = ../stm-audio-bootloader/fsk/packet_decoder.o bootloader.o
OBJS += $(SRC:%.c=$(OBJDIR)/%.o)
OBJS += Startup.o

# C dependencies echoed into Makefile
DEP = $(OBJS:.o=.d)  # one dependency file for each source


all: $(TARGET).hex $(BIN)

# include all DEP files in the makefile
# will rebuild elements if dependent C headers are changed
-include $(DEP)

$(TARGET).hex: $(EXECUTABLE)
	@$(CP) -O ihex $^ $@

$(EXECUTABLE): $(OBJS)
	@$(LD) -g $(MCFLAGS) $(LDFLAGS) $(OBJS) $(LIBS) -o $@
	@echo "linked:       $@"
	@$(OBJDUMP) --disassemble $@ > $@.lst
	@echo "disassembly:  $@.lst"

$(BIN): $(EXECUTABLE)
	@$(CP) -O binary $< $@
	@echo "binary:       $@"
	@$(OBJDUMP) -x --syms $< > $(addsuffix .dmp, $(basename $<))
	@echo "symbol table: $@.dmp"
	@echo "Release: "$(R)
	- @stat -x $(TARGET).bin | grep 'Size'
	@echo "        ^ must be less than 64kB (65,536)"

flash: $(BIN)
	st-flash write $(BIN) 0x08000000

%.o: %.c
	@$(CC) -ggdb $(CFLAGS) $(C99) -c $< -o $@
	@echo $@

%.o: %.cc
	@$(CXX) -c $(CPPFLAGS) $< -o $@
	@echo $@

%.d: %.c
	@$(CC) $(CFLAGS) $< -MM -MT $(@:.d=.o) >$@

%.s: %.c
	@$(CC) -ggdb $(CFLAGS) -S $< -o $@

Startup.o: $(STARTUP)
	@$(CC) $(CFLAGS) $(C99) -c $< -o $@
	@echo $@

wav: fsk-wav

fsk-wav: $(BIN)
	export "PYTHONPATH=$$PYTHONPATH:'.'"
	cd .. && python stm_audio_bootloader/fsk/encoder.py \
		-s 48000 -b 16 -n 8 -z 4 -p 256 -g 16384 -k 1800 \
		$(PRJ_DIR)/$(BIN)

erase:
	st-flash erase

clean:
	@rm -f Startup.lst $(TARGET).elf.lst $(OBJS) $(AUTOGEN) \
	$(TARGET).bin  $(TARGET).out  $(TARGET).hex \
	$(TARGET).map  $(TARGET).dmp  $(EXECUTABLE) $(DEP)
