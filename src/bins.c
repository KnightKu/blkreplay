/* Copyright 2009-2012 Thomas Schoebel-Theuer /  1&1 Internet AG
 *
 * Email: tst@1und1.de
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 */

#define _GNU_SOURCE
#include <config.h>

#include <stdio.h>

#include <math.h>

#if !HAVE_DECL_EXP10
# define exp10(x) (exp((x) * log(10)))
#endif

#define MAX_BINS (1024 * 1024 * 8)

double bin_subdiv = 10.0;
int bin_min = MAX_BINS;
int bin_max = 0;
int bin_count[MAX_BINS];

void put_bin(double val)
{
	int bin;

	if (val <= 0)
		return;

	bin = log10(val) * bin_subdiv;
	bin += MAX_BINS/2;
	if (bin < 0 || bin >= MAX_BINS)
		return;

	bin_count[bin]++;

	if (bin < bin_min)
		bin_min = bin;
	if (bin >= bin_max)
		bin_max = bin + 1;
}

int main(int argc, const char *argv[])
{
	int i;
	char buf[4096];

	if (argc > 1) {
		bin_subdiv = atof(argv[1]);
	}
	
	while (fgets(buf, sizeof(buf), stdin)) {
		double val = 0;
		sscanf(buf, " %lf", &val);
		put_bin(val);
	}

	for (i = bin_min; i < bin_max; i++) {
		printf("%le %6d\n", exp10((double)(i - MAX_BINS/2) / bin_subdiv), bin_count[i]);
	}

	return 0;
}
