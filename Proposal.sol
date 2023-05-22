// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

import "./IExecutableProposal.sol";

contract SampleProposal is IExecutableProposal {
    event ProposalExecuted(uint proposalId, uint numVotes, uint numTokens, uint balance);

    function executeProposal(uint proposalId, uint numVotes, uint numTokens) external payable override {
        emit ProposalExecuted(proposalId, numVotes, numTokens, address(this).balance);
    }
}