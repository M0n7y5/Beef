using System;

namespace Tests
{
	class Ternary
	{
		const int A = 100;
		const int B = 200;

		static int[64] sSeen;
		static int sChecks;

		static void E(int idx, int got, int want)
		{
			Test.Assert(got == want);
			sSeen[idx] |= (got == A) ? 1 : 2;
			sChecks = Math.Max(sChecks, idx + 1);
		}

		static int Id(int v) => v;
		static int Sum(int l, int r) => l + r;

		static int ReturnExpr(int x, int y) => x - y < 0 ? A : B;

		static int ReturnStmt(int n)
		{
			return n % 2 == 1 ? A : B;
		}

		static void Check(int x, int y, int n, bool f)
		{
			int a = A;
			int b = B;

			E(0, x - y < 0 ? a : b, ((x - y) < 0) ? a : b);
			E(1, n % 2 == 1 ? a : b, ((n % 2) == 1) ? a : b);
			E(2, x < 0 ? a : b, (x < 0) ? a : b);
			E(3, x > 0 ? a : b, (x > 0) ? a : b);
			E(4, x == 1 ? a : b, (x == 1) ? a : b);
			E(5, x != 1 ? a : b, (x != 1) ? a : b);
			E(6, (x < 0) ? a : b, (x < 0) ? a : b);
			E(7, x < y ? a : b, (x < y) ? a : b);

			E(8, x + 1 > 0 ? a : b, ((x + 1) > 0) ? a : b);
			E(9, x * y + n > 0 ? a : b, (((x * y) + n) > 0) ? a : b);
			E(10, x - y == 0 ? a : b, ((x - y) == 0) ? a : b);
			E(11, x & 1 == 1 ? a : b, ((x & 1) == 1) ? a : b);
			E(12, x < 0 && f ? a : b, ((x < 0) && f) ? a : b);
			E(13, x - y > 0 && f ? a : b, (((x - y) > 0) && f) ? a : b);
			E(14, x == 1 == f ? a : b, ((x == 1) == f) ? a : b);
			E(15, x < 0 || f ? a : b, ((x < 0) || f) ? a : b);
			E(16, x < 0 && y > 0 ? a : b, ((x < 0) && (y > 0)) ? a : b);
			E(17, x < 0 || y > 0 ? a : b, ((x < 0) || (y > 0)) ? a : b);
			E(18, x < 0 && y + 1 > 0 ? a : b, ((x < 0) && ((y + 1) > 0)) ? a : b);
			E(19, f && x - y < 0 ? a : b, (f && ((x - y) < 0)) ? a : b);
			E(20, f && f ? a : b, (f && f) ? a : b);
			E(21, !(x < 0) ? a : b, (!(x < 0)) ? a : b);
			E(22, (x - y < 0) ? a : b, ((x - y) < 0) ? a : b);
			E(23, (x - y) < 0 ? a : b, ((x - y) < 0) ? a : b);

			E(24, x < 0 ? a : y > 0 ? b : n, (x < 0) ? a : ((y > 0) ? b : n));
			E(25, x - y < 0 ? a : n % 2 == 1 ? b : x, ((x - y) < 0) ? a : (((n % 2) == 1) ? b : x));
			E(26, x < 0 ? y > 0 ? a : b : n, (x < 0) ? ((y > 0) ? a : b) : n);
			E(27, x - y < 0 ? n % 2 == 1 ? a : b : x + 1, ((x - y) < 0) ? (((n % 2) == 1) ? a : b) : (x + 1));
			E(28, x - y < 0 ? a : b + n, ((x - y) < 0) ? a : (b + n));
			E(29, x < 0 ? a + 1 - 1 : b * 2 / 2, (x < 0) ? ((a + 1) - 1) : ((b * 2) / 2));

			bool? bn = (n == 1) ? (bool?)null : (bool?)(y > 0);
			E(30, bn ?? f ? a : b, (bn ?? f) ? a : b);
			E(31, bn ?? x - y < 0 ? a : b, (bn ?? ((x - y) < 0)) ? a : b);

			String str = scope .("s");
			Object obj = f ? str : null;
			E(32, obj is String && x < 0 ? a : b, ((obj is String) && (x < 0)) ? a : b);
			E(33, (obj as String) != null && x - y < 0 ? a : b, (((obj as String) != null) && ((x - y) < 0)) ? a : b);
			E(34, (int)(x * 2) - y < 0 ? a : b, ((((int)(x * 2)) - y) < 0) ? a : b);
			E(35, (float)x - y < 0.5f ? a : b, ((((float)x) - y) < 0.5f) ? a : b);

			E(36, !f && x < 0 ? a : b, ((!f) && (x < 0)) ? a : b);
			E(37, -x + y < 0 ? a : b, (((-x) + y) < 0) ? a : b);

			E(38, x << 1 | 1 > 2 ? a : b, (((x << 1) | 1) > 2) ? a : b);
			E(39, x ^ y & 3 == 0 ? a : b, ((x ^ (y & 3)) == 0) ? a : b);

			E(40, x < 0 && y > 0 || n == 2 ? a : b, (((x < 0) && (y > 0)) || (n == 2)) ? a : b);
			E(41, x - 1 < 0 || y + 1 > 0 && f ? a : b, (((x - 1) < 0) || (((y + 1) > 0) && f)) ? a : b);

			E(42, Id(x - y < 0 ? a : b), ((x - y) < 0) ? a : b);
			E(43, Sum(x - y < 0 ? a : b, n % 2 == 1 ? a : b) - (((n % 2) == 1) ? a : b), ((x - y) < 0) ? a : b);
			E(44, ReturnExpr(x, y), ((x - y) < 0) ? a : b);
			E(45, ReturnStmt(n), ((n % 2) == 1) ? a : b);
			int r = 0;
			r = x - y < 0 ? a : b;
			E(46, r, ((x - y) < 0) ? a : b);
			r = 0;
			r += n % 2 == 1 ? a : b;
			E(47, r, ((n % 2) == 1) ? a : b);

			int? v = x - y < 0 ? (int?)1 : null;
			Test.Assert(v == (((x - y) < 0) ? (int?)1 : null));
		}

		[Test]
		public static void TestPrecedence()
		{
			for (int x in -2...3)
				for (int y in -1...2)
					for (int n in 1...2)
					{
						Check(x, y, n, true);
						Check(x, y, n, false);
					}

			for (int idx < sChecks)
				Test.Assert(sSeen[idx] == 3);
		}
	}
}
