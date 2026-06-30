from setuptools import find_packages, setup

package_name = 'fpga_bridge'

setup(
    name=package_name,
    version='0.1.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='Mirthun Mohan',
    maintainer_email='mirthmoh@gmail.com',
    description='Reads the Tang Nano 20K FPGA UART packet stream and republishes /acoustic/* topics.',
    license='MIT',
    tests_require=['pytest'],
    entry_points={
        'console_scripts': [
            'fpga_uart_node = fpga_bridge.fpga_uart_node:main',
        ],
    },
)
