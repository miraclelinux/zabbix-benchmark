#export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig
HGL_CFLAGS=`pkg-config --cflags history-gluon-1.0`
HGL_LIBS=`pkg-config --libs history-gluon-1.0`

hgl-setup-dummy-data:
	cc $(HGL_CFLAGS) $(HGL_LIBS) -lstdc++ $@.cc -o $@

clean:
	rm hgl-setup-dummy-data
