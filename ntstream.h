/*
 * $Id: ntstream.h,v 1.1 2003/01/25 15:10:04 andrew_belov Exp $
 * ---------------------------------------------------------------------------
 * Prototypes of the functions located in NTSTREAM.C are declared here.
 *
 *
 */

#ifndef NTSTREAM_INCLUDED
#define NTSTREAM_INCLUDED

#if TARGET==WIN32

#ifdef __MINGW32__
/* largeint.h came with old Win32 SDKs and is absent from MinGW-w64. Provide
   the two helpers NTSTREAM.C uses, on LARGE_INTEGER.QuadPart (signed 64-bit). */
static __inline LARGE_INTEGER ConvertUlongToLargeInteger(ULONG value)
{
 LARGE_INTEGER result;

 result.QuadPart=(LONGLONG)value;
 return(result);
}

static __inline LARGE_INTEGER LargeIntegerSubtract(LARGE_INTEGER minuend, LARGE_INTEGER subtrahend)
{
 LARGE_INTEGER result;

 result.QuadPart=minuend.QuadPart-subtrahend.QuadPart;
 return(result);
}
#else
#include <largeint.h>
#endif

/* Read/write (backup/restore) modes */

#define NTSTREAMS_READ             0
#define NTSTREAMS_WRITE            1

/* NT stream operations structure */

struct nt_sid
{
 HANDLE hf;                             /* Win32 file handle */
 LARGE_INTEGER rem;                     /* Bytes remaining in xaction */
 int is_write;                          /* 1 = write */
 LPVOID lpcontext;                      /* !NULL = need to finalize */
};

/* Prototypes */

struct nt_sid *open_streams(char *name, int is_write);
void close_streams(struct nt_sid *sid);
int next_stream(WIN32_STREAM_ID *dest, struct nt_sid *sid);
unsigned long seek_stream_id(DWORD id, struct nt_sid *sid);
unsigned long read_stream(unsigned char *dest, unsigned long bytes, struct nt_sid *sid);
int create_stream(WIN32_STREAM_ID *src, struct nt_sid *sid);
unsigned long write_stream(unsigned char *src, unsigned long bytes, struct nt_sid *sid);

#endif  /* TARGET==WIN32 */

#endif
