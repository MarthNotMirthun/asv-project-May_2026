from setuptools import find_packages, setup

package_name = 'vehicle_control'

setup(
    name=package_name,
    version='0.1.0',
    packages=find_packages(exclude=['test']),
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        ('share/' + package_name + '/config', ['config/ekf_params.yaml']),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='Mirthun Mohan',
    maintainer_email='mirthmoh@gmail.com',
    description='Motor driver bridge, collision safety override, and dead-reckoning nodes.',
    license='MIT',
    tests_require=['pytest'],
    entry_points={
        'console_scripts': [
            'motor_driver_node = vehicle_control.motor_driver_node:main',
            'collision_safety_node = vehicle_control.collision_safety_node:main',
            'dead_reckoning_node = vehicle_control.dead_reckoning_node:main',
        ],
    },
)
