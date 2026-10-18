#ifndef PRIVATEROOM_OLM_H
#define PRIVATEROOM_OLM_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
char *pr_olm_execute(const uint8_t *input, size_t len);
void pr_olm_free(char *buffer);
#ifdef __cplusplus
}
#endif
#endif
