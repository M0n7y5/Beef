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
		// The leaked object's address, for the test script to evaluate. An int doesn't keep it alive.
		public static int sLeakedAddr;
		public static int sLoops;

		static void Leak()
		{
			Leaked leaked = new Leaked();
			sLeakedAddr = (int)Internal.UnsafeCastToPtr(leaked);
		}

		// Overwrites the stack Leak() used, so no stale copy of the pointer keeps the object alive
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
			// Ten seconds: the periodic collection reports the leak well before the end
			while (sLoops < 200)
			{
				sLoops++;
				Thread.Sleep(50);
			}
			return result;
		}
	}
}
