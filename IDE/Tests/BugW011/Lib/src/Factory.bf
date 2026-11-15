namespace Lib
{
	class Factory
	{
		public static int sMade;
		public static int sPlain;

		public static T Make<T>() where T : new, class
		{
			sMade++;
			/*Change
			sMade += 10;
			*/
			return new T();
		}

		public static void Plain()
		{
			sPlain++;
			/*ChangePlain
			sPlain += 10;
			*/
		}
	}
}
