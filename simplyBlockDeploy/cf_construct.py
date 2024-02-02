
import sys
import json
from cfnlint.api import lint_all

def cf_construct(namespace="default", instances=None, region=None):
    print(region)
    # data var will be the content of the instances.yaml
    cf = {
        "AWSTemplateFormatVersion": "2010-09-09",
        "Resources": {}
    }

    cf["Resources"]["PlacementGroup"] = PlacementGroup()
    cf["Resources"]["PubPrivateVPC"] = PubPrivateVPC(namespace)
    cf["Resources"]["PublicSubnet"] = PublicSubnet(namespace, region["SpecifiedAz"])
    cf["Resources"]["PrivateSubnet"] = PrivateSubnet(namespace, region["SpecifiedAz"])
    cf["Resources"]["InternetGateway"] = InternetGateway(namespace)
    cf["Resources"]["GatewayToInternet"] = GatewayToInternet()
    cf["Resources"]["PublicRouteTable"] = PublicRouteTable() 
    cf["Resources"]["PublicRoute"] = PublicRoute()
    cf["Resources"]["PublicSubnetRouteTableAssociation"] = PublicSubnetRouteTableAssociation()
    cf["Resources"]["NatGateway"] = NatGateway(namespace)
    cf["Resources"]["NatPublicIP"] = NatPublicIP(namespace)
    cf["Resources"]["PrivateRouteTable"] = PrivateRouteTable()
    cf["Resources"]["PrivateRoute"] = PrivateRoute()
    cf["Resources"]["PrivateSubnetRouteTableAssociation"] = PrivateSubnetRouteTableAssociation()
    cf["Resources"]["VPCDefaultSecurityGroupIngress"] = VPCDefaultSecurityGroupIngress()
    cf["Resources"][namespace] = sshKey(namespace, instances['PublicKeyMaterial'])

    for instance in instances["instances"]:
        instance['Name'] =  "{}{}".format(namespace, instance['Name'])
        cf["Resources"][instance['Name']] = Instance(namespace, instance, instances["ImageId"])
        if 'EBS' in instance:
            BlockDeviceMappings = []
            print(instance['EBS'])

            for volume in instance['EBS']:
                BlockDeviceMappings.append(EbsVolume(volume["Size"], volume["DeviceName"]))
            cf["Resources"][instance["Name"]]["Properties"]["BlockDeviceMappings"] = BlockDeviceMappings

    # This produces some output which can be very useful in diagnosing bad cf templates.
    for lint in lint_all(json.dumps(cf)):
        print("linter:", lint)
    
    return cf

def main(argv):
    cf_construct()

if __name__ == "__main__":
   main(sys.argv[1:])


## CF templating functions
def PlacementGroup(): 
    return {
                "Type": "AWS::EC2::PlacementGroup",
                "Properties": {
                    "Strategy": "cluster"
                }
           }

def PubPrivateVPC(namespace): 
    return {
                "Type": "AWS::EC2::VPC",
                "Properties": {
                    "EnableDnsHostnames": True,
                    "CidrBlock": "10.141.0.0/23",
                    "Tags": [
                        {
                            "Key": "Name",
                            "Value": namespace
                        }
                    ]
                }
            }

def PublicSubnet(namespace, az):
    return {
                "Type": "AWS::EC2::Subnet",
                "Properties": {
                    "VpcId": {
                        "Ref": "PubPrivateVPC"
                    },
                    "AvailabilityZone": az, 
                    "CidrBlock": "10.141.0.0/24",
                    "MapPublicIpOnLaunch": True,
                    "Tags": [
                        {
                            "Key": "Name",
                            "Value": namespace
                        }
                    ]
                }
            }

def PrivateSubnet(namespace, az): 
    return {
                "Type": "AWS::EC2::Subnet",
                "Properties": {
                    "VpcId": {
                        "Ref": "PubPrivateVPC"
                    },
                    "CidrBlock": "10.141.1.0/24",
                    "AvailabilityZone": az,
                    "MapPublicIpOnLaunch": False,
                    "Tags": [
                        {
                            "Key": "Name",
                            "Value": namespace
                        }
                    ]
                }
            }

def InternetGateway(namespace):
    return {
                "Type": "AWS::EC2::InternetGateway",
                "Properties": {
                    "Tags": [
                        {
                            "Key": "Name",
                            "Value": namespace
                        }
                    ]
                }
            }

def GatewayToInternet():
    return {
                "Type": "AWS::EC2::VPCGatewayAttachment",
                "Properties": {
                    "VpcId": {
                        "Ref": "PubPrivateVPC"
                    },
                    "InternetGatewayId": {
                        "Ref": "InternetGateway"
                    }
                }
            }

def PublicRouteTable(): 
    return {
                "Type": "AWS::EC2::RouteTable",
                "Properties": {
                    "VpcId": {
                        "Ref": "PubPrivateVPC"
                    }
                }
            }
    
def PublicRoute(): 
    return {
                "Type": "AWS::EC2::Route",
                "DependsOn": "GatewayToInternet",
                "Properties": {
                    "RouteTableId": {
                        "Ref": "PublicRouteTable"
                    },
                    "DestinationCidrBlock": "0.0.0.0/0",
                    "GatewayId": {
                        "Ref": "InternetGateway"
                    }
                }
            }
     
def PublicSubnetRouteTableAssociation(): 
     return {
                "Type": "AWS::EC2::SubnetRouteTableAssociation",
                "Properties": {
                    "SubnetId": {
                        "Ref": "PublicSubnet"
                    },
                    "RouteTableId": {
                        "Ref": "PublicRouteTable"
                    }
                }
            }

def NatGateway(namespace): 
    return {
                "Type": "AWS::EC2::NatGateway",
                "DependsOn": "NatPublicIP",
                "Properties": {
                    "SubnetId": {
                        "Ref": "PublicSubnet"
                    },
                    "AllocationId": {
                        "Fn::GetAtt": [
                            "NatPublicIP",
                            "AllocationId"
                        ]
                    },
                    "Tags": [
                        {
                            "Key": "Name",
                            "Value": namespace
                        }
                    ]
                }
            }

def NatPublicIP(namespace): 
    return {
                "Type": "AWS::EC2::EIP",
                "DependsOn": "PubPrivateVPC",
                "Properties": {
                    "Domain": "vpc",
                    "Tags": [
                        {
                            "Key": "Name",
                            "Value": namespace
                        }
                    ]
                }
            }
     
def PrivateRouteTable(): 
    return {
                "Type": "AWS::EC2::RouteTable",
                "Properties": {
                    "VpcId": {
                        "Ref": "PubPrivateVPC"
                    }
                }
            }
     
def PrivateRoute(): 
    return {
                "Type": "AWS::EC2::Route",
                "Properties": {
                    "NatGatewayId": {
                        "Ref": "NatGateway"
                    },
                    "RouteTableId": {
                        "Ref": "PrivateRouteTable"
                    },
                    "DestinationCidrBlock": "0.0.0.0/0"
                }
            }
     
def PrivateSubnetRouteTableAssociation(): 
    return {
                "Type": "AWS::EC2::SubnetRouteTableAssociation",
                "Properties": {
                    "SubnetId": {
                        "Ref": "PrivateSubnet"
                    },
                    "RouteTableId": {
                        "Ref": "PrivateRouteTable"
                    }
                }
            }

def VPCDefaultSecurityGroupIngress(): 
    return {
                "Type": "AWS::EC2::SecurityGroupIngress",
                "Properties": {
                    "GroupId": {
                        "Fn::GetAtt": [
                            "PubPrivateVPC",
                            "DefaultSecurityGroup"
                        ]
                    },
                    "IpProtocol": "tcp",
                    "FromPort": 22,
                    "ToPort": 22,
                    "CidrIp": "0.0.0.0/0"
                }
            }

def sshKey(Name, PublicKeyMaterial):
    return {
                "Type": "AWS::EC2::KeyPair",
                "Properties": {
                    "KeyName": Name,
                    "KeyFormat": "pem",
                    "KeyType": "rsa",
                    "PublicKeyMaterial": PublicKeyMaterial,
                    "Tags": [
                        {
                            "Key": "Name",
                            "Value": Name
                        }
                    ]
                }
            }

def EbsVolume(size, device_name):
    return {
                "DeviceName" : device_name,
                "Ebs" : {
                "VolumeType" : "gp3",
                "VolumeSize" : size
                }
            }

def Instance(namespace, instance_dict, ami):
    return {
                "Type": "AWS::EC2::Instance",
                "Properties": {
                    "InstanceType": instance_dict["InstanceType"],
                    "ImageId": ami,
                    "KeyName": {
                        "Ref": namespace
                    },
                    "NetworkInterfaces": [
                        {
                            "DeleteOnTermination": True,
                            "DeviceIndex": 0,
                            "SubnetId": {
                                "Ref": instance_dict["SubnetId"]
                            }
                        }
                    ],
                    "Tags": [
                        {
                            "Key": "Name",
                            "Value": instance_dict["Name"]
                        },
                        {
                            "Key": "Role",
                            "Value": instance_dict["Role"]
                        }
                    ]
                }
            }
