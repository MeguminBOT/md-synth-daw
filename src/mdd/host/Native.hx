package mdd.host;

@:buildXml('
<files id="haxe">
	<compilerflag value="-I${SDL3PATH}/include" />
	<compilerflag value="-I${MINIAUDIOPATH}" />
	<compilerflag value="-I${STBPATH}" />
	<compilerflag value="-I${NATIVEPATH}" />
</files>
<files id="__main__">
	<compilerflag value="-I${SDL3PATH}/include" />
	<compilerflag value="-I${MINIAUDIOPATH}" />
	<compilerflag value="-I${STBPATH}" />
	<compilerflag value="-I${NATIVEPATH}" />
</files>
<files id="mdd_native">
	<compilerflag value="-I${SDL3PATH}/include" />
	<compilerflag value="-I${MINIAUDIOPATH}" />
	<compilerflag value="-I${STBPATH}" />
	<compilerflag value="-I${NATIVEPATH}" />
	<file name="${NATIVEPATH}/window.cpp" />
	<file name="${NATIVEPATH}/events.cpp" />
</files>
<target id="haxe">
	<lib name="${SDL3PATH}/lib/SDL3.lib" if="windows" />
	<lib name="-lSDL3" unless="windows" />
	<files id="mdd_native" />
</target>
')
class Native {
	public static function ready():Void {}
}
