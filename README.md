# protoc-gen-swift

proto -> swift

## Example

your proto files

```
docker run --rm\
 -v $(pwd):$(pwd) -w $(pwd)\
 sagadash/protoc-gen-swift\
 --swift_opt=Visibility=Public\
 --swift_out=models --swiftgrpc_out=models\
 -Iproto proto/**/*.proto
```

## Refs

* https://github.com/znly/docker-protobuf
  * Delete except Swift.
* https://github.com/grpc/grpc-swift
