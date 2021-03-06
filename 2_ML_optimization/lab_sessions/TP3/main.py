import pickle
import argparse
import os

from torch.utils.data import DataLoader
import torch.optim as optim

from torchvision.datasets import FashionMNIST
from utils.metrics import *
from models import *
from datasets import *
from client import *
from server import *
from learner import *

INDICES_PATH = "data/indices"
MNIST_PATH = "data/mnist"


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        '--n_rounds',
        help='number of communication rounds;',
        type=int)
    parser.add_argument(
        '--lr',
        help='number of clients;',
        type=float,
        default=1e-2)
    parser.add_argument(
        '--local_epochs',
        help='number of local epochs;',
        type=int,
        default=1)
    parser.add_argument(
        '--local_rank',
        type=int)
    parser.add_argument(
        '--seed',
        help='seed for the random processes;',
        type=int,
        default=1234,
        required=False)
    return parser.parse_args()


def main():
    args = parse_args()

    dist.init_process_group(backend='gloo', init_method="env://")

    rank = dist.get_rank()
    model = LinearModel()
    criterion = nn.CrossEntropyLoss()
    metric = accuracy
    device = torch.device("cpu")

    optimizer = optim.SGD([param for param in model.parameters() if param.requires_grad],
                          lr=args.lr,
                          momentum=0.9,
                          weight_decay=5e-4)

    learner = Learner(model=model,
                      criterion=criterion,
                      metric=metric,
                      device=device,
                      optimizer=optimizer)

    if rank == 0:
        # create test loader for MNIST dataset
        transform = Compose([
            ToTensor(),
            Normalize((0.1307,), (0.3081,))
        ])
        dataset = FashionMNIST(MNIST_PATH, train=False, transform=transform)
        loader = DataLoader(dataset, shuffle=False, batch_size=128)

        server = Server(learner=learner,
                        test_loader=loader,
                        logger=None,
                        log_freq=5)

        server.run(n_rounds=args.n_rounds)

    else:
        indices_path = os.path.join(INDICES_PATH, f"client_{rank}.pkl")
        with open(indices_path, "rb") as f:
            indices = pickle.load(f)

        # Find a way to get world size
        client_weight = 1 / (dist.get_world_size()-1)

        dataset = SubMNIST(MNIST_PATH, indices)
        loader = DataLoader(dataset, shuffle=True, batch_size=32)
        client = Client(learner, loader, client_weight, local_epochs=1, device=device)
        client.run(n_rounds=args.n_rounds)


if __name__ == "__main__":
    main()
