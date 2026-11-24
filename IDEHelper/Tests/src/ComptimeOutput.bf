using System;

namespace Tests
{
	class ComptimeOutput
	{
		[Comptime]
		static int Say()
		{
			Compiler.Output("ComptimeOutput test line\n");
			return 3;
		}

		const int cSaid = Say();

		[Test]
		public static void TestOutputAtComptime()
		{
			Test.Assert(cSaid == 3);
		}
	}
}
