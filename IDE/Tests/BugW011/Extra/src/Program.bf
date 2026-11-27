using System;

namespace Extra
{
	class Thing
	{
		public int mValue = 7;
	}

	class Program
	{
		public static void Main()
		{
			delete Lib.Factory.Make<Thing>();
		}
	}
}
