API="https://api.vpsfree.cz"
VERSION=1
USERNAME=
PASSWORD=

.PHONY: install

install:
	./install.rb ${API} ${VERSION} ${USERNAME} ${PASSWORD}
