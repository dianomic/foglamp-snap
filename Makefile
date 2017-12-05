all:

install:
	install -D -m755 wrappers/wrapper-foglamp $(DESTDIR)/usr/bin/wrapper-foglamp
