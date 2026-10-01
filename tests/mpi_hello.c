#include <mpi.h>
#include <stdio.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    MPI_Init(&argc, &argv);
    int rank = 0;
    int size = 0;
    char hostname[256] = {0};
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    gethostname(hostname, sizeof(hostname) - 1);
    printf("rank=%d size=%d hostname=%s\n", rank, size, hostname);
    fflush(stdout);
    MPI_Finalize();
    return 0;
}