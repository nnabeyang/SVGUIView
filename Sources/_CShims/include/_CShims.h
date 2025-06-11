#ifndef CSHIMS_H
#define CSHIMS_H

#include <locale.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

extern double strtod_l(const char * _Nullable __restrict nptr, char * _Nullable * _Nullable __restrict endptr, locale_t _Nullable loc);
extern unsigned long long strtoull_l(const char * _Nullable __restrict nptr, char * _Nullable * _Nullable __restrict endptr, int base,locale_t _Nullable loc);
#ifdef __cplusplus
}
#endif

#endif /* CSHIMS_H */
