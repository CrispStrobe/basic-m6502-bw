CA65  = ca65
LD65  = ld65
CFG   = basic.cfg

SRC   = basic.s
OBJ   = basic.o
ROM   = basic.rom

.PHONY: all clean

all: $(ROM)

$(OBJ): $(SRC)
	$(CA65) -t none -o $@ $<

$(ROM): $(OBJ) $(CFG)
	$(LD65) -C $(CFG) -o $@ $<

clean:
	rm -f $(OBJ) $(ROM)
