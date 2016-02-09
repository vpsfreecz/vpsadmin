API="https://api.vpsfree.cz"
VERSION=2.0
USERNAME=
PASSWORD=

.PHONY: install

install:
	./install.rb ${API} ${VERSION} ${USERNAME} ${PASSWORD}
