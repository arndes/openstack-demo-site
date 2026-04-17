IMAGE  = openstack-demo.qcow2
SIZE   = 4G
ROOTPW = demo

BASE_URL   = https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
BASE_CACHE = $(HOME)/.cache/ubuntu-cloud-images/noble-server-cloudimg-amd64.img

.PHONY: all clean

all: $(IMAGE)

$(BASE_CACHE):
	mkdir -p $(dir $(BASE_CACHE))
	wget -O $(BASE_CACHE) $(BASE_URL)

$(IMAGE): web/index.html nginx/default $(BASE_CACHE)
	qemu-img convert -f qcow2 -O qcow2 $(BASE_CACHE) $(IMAGE)
	qemu-img resize $(IMAGE) $(SIZE)
	virt-customize -a $(IMAGE) \
	  --root-password password:$(ROOTPW) \
	  --run-command "growpart /dev/sda 1" \
	  --run-command "resize2fs /dev/sda1" \
	  --run-command "printf 'disable_root: false\n' > /etc/cloud/cloud.cfg.d/99-root.cfg" \
	  --install nginx \
	  --copy-in web/index.html:/var/www/html/ \
	  --copy-in nginx/default:/etc/nginx/sites-available/ \
	  --run-command "systemctl enable nginx" \
	  --run-command "apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*"
	virt-sysprep -a $(IMAGE) --operations defaults,-ssh-hostkeys
	virt-sparsify --in-place $(IMAGE)
	@echo ""
	@echo "Build complete: $(IMAGE)"
	@echo "  Root password : $(ROOTPW)"
	@echo ""
	@echo "Test locally:"
	@echo "  qemu-system-x86_64 -m 512 -drive file=$(IMAGE),format=qcow2 \\"
	@echo "    -netdev user,id=net0,hostfwd=tcp::8080-:80 -device virtio-net,netdev=net0 \\"
	@echo "    -nographic"
	@echo ""
	@echo "Then open http://localhost:8080 in your browser."
	@echo ""

clean:
	rm -f $(IMAGE)
