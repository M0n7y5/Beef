using System;

namespace Tests
{
	class UsingStatements
	{
		class Tracker
		{
			public int mDisposed;
		}

		struct Scope : IDisposable
		{
			public Tracker mTracker;
			public int mId;

			public this(Tracker tracker, int id)
			{
				mTracker = tracker;
				mId = id;
			}

			public void Dispose()
			{
				mTracker.mDisposed += mId;
			}
		}

		class Builder
		{
			public Tracker mTracker = new .() ~ delete _;

			public Scope Open(int id) => .(mTracker, id);
		}

		static int Pick(Builder b, bool cond)
		{
			using (cond ? b.Open(1) : b.Open(10))
			{
			}
			return b.mTracker.mDisposed;
		}

		[Test]
		public static void TestConditionalExpression()
		{
			Test.Assert(Pick(scope Builder(), true) == 1);
			Test.Assert(Pick(scope Builder(), false) == 10);

			Builder b = scope .();
			bool cond = true;
			using (!cond ? b.Open(100) : b.Open(1000))
			{
			}
			Test.Assert(b.mTracker.mDisposed == 1000);
		}

		[Test]
		public static void TestDeclarations()
		{
			Builder b = scope .();
			using (var s = b.Open(1))
			{
				Test.Assert(s.mId == 1);
			}
			using (let s = b.Open(2))
			{
				Test.Assert(s.mId == 2);
			}
			using (Scope s = b.Open(4))
			{
				Test.Assert(s.mId == 4);
			}
			using (Scope? s = b.Open(8))
			{
				Test.Assert(s.Value.mId == 8);
			}
			using (b.Open(16))
			{
			}
			Test.Assert(b.mTracker.mDisposed == 1 + 2 + 4 + 8 + 16);
		}
	}
}
