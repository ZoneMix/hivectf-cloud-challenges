NAME := wom

CFLAGS := -Wall

CC := gcc

all: $(NAME).c
	$(CC) $(CFLAGS) -o challenge/$(NAME).bin $(NAME).c
	patchelf --set-interpreter ./ld-2.31.so ./challenge/$(NAME).bin
	patchelf --set-rpath '.' ./challenge/$(NAME).bin

clean:
	rm -rf $(NAME).bin
