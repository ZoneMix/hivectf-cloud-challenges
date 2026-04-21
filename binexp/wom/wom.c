#include <signal.h>  // for signal, SIGALRM, size_t
#include <stdio.h>   // for printf, NULL, setvbuf, _IONBF, getchar, scanf
#include <stdlib.h>  // for exit, free, getenv, malloc
#include <unistd.h>  // for alarm, chdir, read

/*
 * Signetics Model 25120 Fully-encoded, 9046 x N Random Access, Write Only Memory Emulator
 * https://web.archive.org/web/20060317085650/http://www.national.com/rap/files/datasheet.pdf
 *
 * This software module is suitable for inclusion into any project requiring absolute security
 * and First In, Never Out (FINO) memory access. Also, this module is perfect for organizations
 * with strict data retention policies.
 *
 * Users can instantiate as many as 32 WOM instances to hold their important data. If they run
 * out, user may set any full WOM free and rest assured that they met their regulatory retention
 * requirements, and may reuse that WOM slot for new data [effectivly, infinite storage!]
 *
 */

void sig_handler(int signum) {

	printf("Timeout\n");
	exit(0);

}

void init() {

	alarm(60);
	signal(SIGALRM, sig_handler);

	setvbuf(stdin, NULL, _IONBF, 0);
	setvbuf(stdout, NULL, _IONBF, 0);
	setvbuf(stderr, NULL, _IONBF, 0);

	chdir(getenv("HOME"));

}

int get_int() {

	int i;

	scanf("%d", &i);
	while (getchar() != '\n');

	return i;

}

int main() {

	char *woms[32] = {0};
	size_t sizes[32] = {0};
	int choice, i;

	init();

	printf("Write Only Memory (WOM) v0.2\n");
	printf("Auditing Compliance Tag: %lld\n\n", (long long)printf >> 12 & 0xfff);
	/*
	 * The specification requires that each WOM run be tagged with a pseudo random value.
	 * Just to be safe, we only expose 12 bits.
	 */

	while (1) {

		printf("(1) New, (2) Edit, (3) Delete, (4) Exit\n");
		printf("Choice: ");
		choice = get_int();

		switch(choice) {

			case 1:	// malloc
				for (i=0; i<32 && woms[i]; i++);
				if (i < 32) {
					printf("Size: ");
					sizes[i] = get_int();
					woms[i] = malloc(sizes[i]);
					printf("WOM saved! (ID#%d)\n", i);
				} else {
					printf("sorry, too many woms\n");
				}
				break;

			case 2: // edit
				printf("WOM ID: ");
				i = get_int();
				if (i >= 0 && i < 32 && woms[i] != NULL) {
					printf("Content: ");
					read(0, woms[i], sizes[i]+1);
				} else
					printf("Invalid note ID\n");
				break;

			case 3: // free
				printf("WOM ID: ");
				i = get_int();
				if (i >= 0 && i < 32 && woms[i] != NULL) {
					free(woms[i]);
					woms[i] = NULL;
				} else
					printf("Invalid note ID\n");
				break;

			case 4: // exit
				exit(0);

			default:
				printf("Invalid choice\n");

		}

	}

	return 0;

}
