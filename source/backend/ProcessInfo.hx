package backend;

#if (cpp && windows)
@:cppFileCode('
#include <windows.h>
struct VxMemCounters
{
	DWORD cb;
	DWORD PageFaultCount;
	SIZE_T PeakWorkingSetSize;
	SIZE_T WorkingSetSize;
	SIZE_T QuotaPeakPagedPoolUsage;
	SIZE_T QuotaPagedPoolUsage;
	SIZE_T QuotaPeakNonPagedPoolUsage;
	SIZE_T QuotaNonPagedPoolUsage;
	SIZE_T PagefileUsage;
	SIZE_T PeakPagefileUsage;
	SIZE_T PrivateUsage;
	SIZE_T PrivateWorkingSetSize;
	ULONG64 SharedCommitUsage;
};
extern "C" BOOL WINAPI K32GetProcessMemoryInfo(HANDLE process, void *counters, DWORD cb);

static double vxMemory()
{
	VxMemCounters m;
	ZeroMemory(&m, sizeof(m));
	m.cb = sizeof(m);
	if (K32GetProcessMemoryInfo(GetCurrentProcess(), &m, sizeof(m)) && m.PrivateWorkingSetSize > 0) return (double)m.PrivateWorkingSetSize;
	m.cb = (DWORD)offsetof(VxMemCounters, PrivateWorkingSetSize);
	if (K32GetProcessMemoryInfo(GetCurrentProcess(), &m, m.cb)) return (double)m.WorkingSetSize;
	return 0.0;
}

static double vxFaults()
{
	VxMemCounters m;
	ZeroMemory(&m, sizeof(m));
	m.cb = (DWORD)offsetof(VxMemCounters, PrivateWorkingSetSize);
	if (K32GetProcessMemoryInfo(GetCurrentProcess(), &m, m.cb)) return (double)m.PageFaultCount;
	return 0.0;
}

static void vxPriority(bool high)
{
	SetPriorityClass(GetCurrentProcess(), high ? ABOVE_NORMAL_PRIORITY_CLASS : NORMAL_PRIORITY_CLASS);
}

static void vxLowThread()
{
	SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_LOWEST);
}
')
#end
class ProcessInfo
{
	static var focused:Bool = false;

	public static function memory():Float
	{
		#if (cpp && windows)
		return untyped __cpp__('vxMemory()');
		#elseif cpp
		return cpp.vm.Gc.memInfo64(cpp.vm.Gc.MEM_INFO_RESERVED);
		#else
		return 0;
		#end
	}

	public static function pageFaults():Float
	{
		#if (cpp && windows)
		return untyped __cpp__('vxFaults()');
		#else
		return 0;
		#end
	}

	public static function lowPriorityThread():Void
	{
		#if (cpp && windows)
		untyped __cpp__('vxLowThread()');
		#end
	}

	public static function setFocused(on:Bool):Void
	{
		#if (cpp && windows)
		if (focused == on) return;
		focused = on;
		untyped __cpp__('vxPriority({0})', on);
		#end
	}
}
