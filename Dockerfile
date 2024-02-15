# The most minimumalistic dockerfile possible.
#  No embedded python support, no unit-testing, 

ARG IMAGE=intersystemsdc/iris-community
FROM $IMAGE

WORKDIR /home/irisowner/dev
COPY .iris_init /home/irisowner/.iris_init

RUN --mount=type=bind,src=.,dst=. \
    iris start IRIS && \
	iris session IRIS < iris.script && \
    iris stop IRIS quietly
