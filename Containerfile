FROM registry.fedoraproject.org/fedora:34

COPY ./ ./

RUN ./hack/dnf_safe update -y \
	&& ./hack/dnf_safe install -y \
		ShellCheck \
		make \
		python3-openstackclient \
		python3-octaviaclient \
		jq \
	&& dnf clean all

WORKDIR /src
