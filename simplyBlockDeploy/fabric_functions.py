import fabric
import json
import os

def run_concurrent_command(namespace=None, instance_list=None, command=None):
    key_filename = "keys/{}".format(namespace)
    print(key_filename)
    if os.path.isfile(key_filename):
        connect_kwargs = {
            "key_filename": key_filename
        }
        connection_list = []
        for machine in instance_list:
            connection_list.append(fabric.Connection(machine, user="rocky", connect_kwargs=connect_kwargs))
        group = fabric.ThreadingGroup.from_connections(connection_list)
        result = group.run(command)
        return result
    else:
        print("Error: Keyfile does not exist.")
        exit(1)

def run_command_return_output(namespace=None, host=None, command=None):
    connect_kwargs = {
        "key_filename": key_filename
    }
    connection = fabric.Connection(host, user="rocky", connect_kwargs=connect_kwargs)
    result = connection.run(command)
    print(result)
    return json.loads(result)