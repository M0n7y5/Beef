using System;

namespace LeakTest
{
	class Leaked
	{
		public int mValue = 42;
	}

	class Program
	{
		public static int sLeakedAddr;

		static void Leak()
		{
			Leaked leaked = new Leaked();
			sLeakedAddr = (int)Internal.UnsafeCastToPtr(leaked);
			int32* raw = new int32[16]*;
			raw[0] = 7;
		}

		public static int Main(String[] args)
		{
			Leak();
			return 0;
		}
	}
}
