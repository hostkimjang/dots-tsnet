/*
 * dots-tsnet: 대화형 SSH(PTY) 보정 라이브러리
 *
 * Dots 컴퓨터의 /dev/pts 는 사용자 그룹으로 만들어지고 tty 그룹(5)이 아닙니다. sshd 는 PTY 를 열 때
 * chown(pty, uid, tty 그룹)을 부르는데, root 가 아니라서 실패하고 접속을 끊습니다("closed by remote host").
 * 이 라이브러리는 /dev/pts/ 아래 경로의 chown 만 성공으로 돌려주고, 나머지 호출은 원래 함수로 넘깁니다.
 * tsnet 과 install.sh 가 dots-tailscale 의 start.sh 를 실행할 때 LD_PRELOAD 로 붙입니다.
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

int chown(const char *path, uid_t owner, gid_t group) {
    static int (*real_chown)(const char *, uid_t, gid_t);
    if (path != NULL && strncmp(path, "/dev/pts/", 9) == 0)
        return 0;
    if (real_chown == NULL)
        real_chown = (int (*)(const char *, uid_t, gid_t))dlsym(RTLD_NEXT, "chown");
    if (real_chown == NULL) {
        errno = ENOSYS;
        return -1;
    }
    return real_chown(path, owner, group);
}
