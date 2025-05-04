#include "fir.h"

void __attribute__ ( ( section ( ".mprjram" ) ) ) initfir() {
	//initial your fir
	for (int i = 0; i < N; i++) {
		inputbuffer[i] = 0;
		outputsignal[i] = 0;
	}
}

int* __attribute__ ( ( section ( ".mprjram" ) ) ) fir(){
	initfir();
	//write down your fir
	for (int i = 0; i < N; i++) {
		int ss_data = inputsignal[i];
		inputbuffer[i] = ss_data;
		for (int j = 0; j <= i; j++) {
			outputsignal[j] += inputbuffer[j] * taps[i - j];
		}
	}
	return outputsignal;
}
		
