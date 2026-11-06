.PHONY: test
test:
	cd tools/accuracy && python3 -m unittest -q test_evaluate
	bash tests/install_test.sh
	bash scripts/build-whisper-lib.sh
	swift test --package-path app
	bash tests/signing_test.sh
