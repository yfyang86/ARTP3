#ifndef BUFFER_BIN_ARTPS
#define BUFFER_BIN_ARTPS

#define BUFFER_FREAD_ENABLE
//#define PRINT_DEB
/*
Task:
Buffer reading binary file,
given file size (nrow ncol)
all data are float

.815
artp3.cpp:
- artp3_chr    L672-683      [x]
- adajoint_chr L924-936      [x]
- artp3        L1059-1069    [skip]

*/

#include <string>
#include <iostream>
#include <fstream>
#include <stdio.h>
#include <stdlib.h>
#include <omp.h>

#ifdef BUFFER_FREAD_ENABLE
#include <fcntl.h>
#endif

// para:
//		filename
//		nrow/ncol
//      output
int segment_read(char *buff, const int len, const int count) {
	return 1;
}

template <class T>
void read_in_buffer(std::string filename, int nrow, int ncol, std::vector<T>& output, int nthread) {

	/*
TODO: READING TO BUFFER;
Verified: testbuffer1.cpp
*/
	std::ios::sync_with_stdio(false);
	size_t mul = sizeof(float) / sizeof(char); // mul >= 2
	const long size_len = (long)nrow*((long)ncol)*mul; // verify size_len == size
	size_t sizeA = nrow*ncol;
	char * buffer ;
	// buffer read, type = float
#ifndef BUFFER_FREAD_ENABLE
buffer = (char *)malloc(sizeof(char)*size_len);
	if (buffer == NULL) {fputs ("Memory error",stderr); exit (2);}
	std::ifstream fin(filename.c_str(), std::ios::in | std::ios::binary);
	fin.read(buffer, size_len);
	fin.close();
#else
  size_t fread_result;
	FILE * fstdin = fopen(filename.c_str(),"rb");
	if (stdin==NULL) {fputs ("File error",stderr); exit (1);}
  buffer = (char*) malloc (sizeof(char)*size_len);
	if (buffer == NULL) {fputs ("Memory error",stderr); exit (2);}
	fread_result=fread(buffer,1,size_len, fstdin);
	if (fread_result != size_len) {fputs ("Reading error",stderr); exit (3);}
	fclose(fstdin);
#endif
#ifdef PRINT_DEB
	float * buffer_float = (float *)buffer;  //TODO: recasting char* to float *
	for (int i = 0; i < nrow; i++) {
		std::cout << "\n[" << i << ",]:\t";
		for (int j = 0; j < ncol; j++)
			std::cout << buffer_float[i*ncol + j] << "\t";
	}
	std::cout << "\n";
#endif
	int i;
#pragma omp parallel
	{
#pragma omp parallel for num_threads(nthread) private(i)  shared(output)
		for (i = 0; i < sizeA; i++) {
			int ii = i%nrow;// Row
			int jj = i/nrow;// Col
			output[ii][jj].stat = ((float *)buffer)[i];
			output[ii][jj].id= jj;
		}
	}
free(buffer);
}
#endif
