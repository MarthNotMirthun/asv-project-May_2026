from setuptools import find_packages, setup

package_name = 'acoustic_homing'

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
    description='SNR-gradient acoustic homing state machine and mission monitor.',
    license='MIT',
    tests_require=['pytest'],
    entry_points={
        'console_scripts': [
            'acoustic_homing_node = acoustic_homing.acoustic_homing_node:main',
            'mission_state_machine = acoustic_homing.mission_state_machine:main',
        ],
    },
)
