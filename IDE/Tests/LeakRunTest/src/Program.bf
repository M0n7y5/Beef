using System;
using System.Threading;

namespace LeakRunTest
{
	class Leaked
	{
		public int mValue = 42;
	}

	class Program
	{
		public static int sLeakedAddr;
		public static int sLoops;

		static void Leak()
		{
			Leaked leaked = new Leaked();
			sLeakedAddr = (int)Internal.UnsafeCastToPtr(leaked);
		}

		static int Scrub()
		{
			uint8[4096] buffer = ?;
			Internal.MemSet(&buffer, 0, buffer.Count);
			return buffer[100];
		}

		public static int Main(String[] args)
		{
			Leak();
			int result = Scrub();
			while (sLoops < 200)
			{
				sLoops++;
				Thread.Sleep(50);
			}
			return result;
		}
	}
}
