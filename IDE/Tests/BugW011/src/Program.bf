#pragma warning disable 168

using System;

namespace Bug
{
	class Thing
	{
		public int mValue = 3;
	}

	class Program
	{
		public static void Main()
		{
			delete Lib.Factory.Make<Thing>();
			Lib.Factory.Plain();
			//Start
			delete Lib.Factory.Make<Thing>();
			Lib.Factory.Plain();
		}
	}
}
