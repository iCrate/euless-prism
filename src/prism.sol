/*
   Copyright 2017 DappHub, LLC

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
*/

import 'ds-token/token.sol';
import 'ds-thing/thing.sol';

contract DSPrism is DSThing {
    struct Slate {
        address[] guys; // Ordered set of candidates. Length is part of list encoding.
    }

    struct Voter {
        uint    weight;
        bytes32 slate; // pointer to slate for reusability
    }

    // top candidates in "lazy decreasing" order by vote
    bool[256**24] public isFinalist; // for address uniqueness checking

    address[] public elected;

    uint public maxVotes;
    DSToken _token;
    mapping(address=>Voter) _voters;
    mapping(address=>uint) _votes;
    mapping(bytes32=>Slate) _slates;


    /**
    @notice Create a DSPrism instance.

    @param electionSize The number of candidates to elect.
    @param token The address of a DSToken instance.
    */
    function DSPrism(DSToken token, uint electionSize) DSThing()
    {
        elected.length = electionSize;
        _token = token;
    }


    /**
    @notice Updates the internal `maxVotes` property with the number of votes
    the specified candidate has if the candidate has more votes than the
    current value.
    */
    function updateMaxVotes(address guy) {
        if (maxVotes < _votes[guy]) {
            maxVotes = _votes[guy];
        }
    }

    /**
    @notice Walks the list of candidates under consideration for election (i.e.,
    those that have been  `swap`ped or `drop`ped into the `elected` set) and
    finds the maximum vote value, updating the internal `maxVotes` property.
    */
    function updateMaxVotes() {
        maxVotes = 0;
        for ( var i = 0 ; i < elected.length ; i++ ) {
            updateMaxVotes(elected[i]);
        }
    }


    /**
    @notice Swap candidates `i` and `j` in the vote-ordered list. This
    transaction will fail if `i` is greater than `j`, if candidate `i` has a
    higher score than candidate `j`, if the candidate one slot below the slot
    candidate `j` is moving to has more votes than candidate `j`, or if
    candidate `j` has fewer than half the votes of the most popular candidate.
    This transaction will always succeed if candidate `j` has at least half the
    votes of the most popular candidate and if candidate `i` either also has
    less than half the votes of the most popular candidate or is `0x0`.

    @dev This function is meant to be called repeatedly until the list of
    candidates, `elected`, has been ordered in descending order by weighted
    votes. The winning candidates will end up at the front of the list.

    @param i The index of the candidate in the `elected` list to move down.
    @param j The index of the candidate in the `elected` list to move up.
    */
    function swap(uint i, uint j) {
        require(i < j && j < elected.length);
        var a = elected[i];
        var b = elected[j];
        elected[i] = b;
        elected[j] = a;
        assert( (_votes[a] >= maxVotes / 2 && _votes[a] < _votes[b]) ||
                (a == 0x0 && _votes[b] >= maxVotes / 2) );
        assert( _votes[elected[i+1]] < _votes[b] || elected[i+1] == 0x0 );

        if (_votes[b] > maxVotes) {
            maxVotes = _votes[b];
        }
    }


    /**
    @notice Replace candidate at index `i` in the set of elected candidates with
    the candidate at address `b`. This transaction will fail if candidate `i`
    has more votes than the candidate at the given address. Address `b` may be
    `0x0` if candidate at index `i` has less than half the votes of the most
    popular candidate.

    @param i The index of the candidate to replace.
    @param b The address of the candidate to insert.
    */
    function drop(uint i, address b) {
        require(i < elected.length);
        var a = elected[i];
        elected[i] = b;
        require(!isFinalist[uint(b)]);
        isFinalist[uint(b)] = true;
        isFinalist[uint(a)] = false;

        assert( (_votes[a] < _votes[b] && _votes[b] >= maxVotes / 2) ||
                (b == 0x0 && _votes[a] < maxVotes / 2));

        if (_votes[b] > maxVotes) {
            maxVotes = _votes[b];
        }
    }


    /**
    @notice Replace candidate at index `i` with `0x0` if they have less than
    half the votes of the most popular candidate.
    */
    function drop(uint i) {
        drop(i, 0x0);
    }


    /**
    @notice Checks membership of `guy` in elected set.
    */
    function isElected(address guy) returns (bool) {
        // "Half votes" rule
        if (_votes[guy] < maxVotes / 2) {
            return false;
        }

        for( var i = 0; i < elected.length - 1; i++ ) {
            if (guy == elected[i]) {
                return true;
            }
        }
        return false;
    }


    /**
    @notice Save an ordered addresses set and return a unique identifier for it.
    */
    function etch(address[] guys) returns (bytes32) {
        requireOrderedSet(guys);
        var key = sha3(guys);
        _slates[key] = Slate({ guys: guys });

        return key;
    }


    /**
    @notice Approve candidates `guys`. This transaction will fail if the set of
    candidates is not ordered according the their numerical values or if it
    contains duplicates. Returns a unique ID for the set of candidates chosen.

    @param guys The ordered set of candidate addresses to approve.
    */
    function vote(address[] guys) returns (bytes32) {
        var slate = etch(guys);
        vote(slate);

        return slate;
    }


    /**
    @notice Returns the number of tokens allocated to voting for `guy`.

    @param guy The address of the candidate whose votes we want to lookup.
    */
    function votes(address guy) constant returns (uint) {
        return _votes[guy];
    }


    /**
    @notice Approve the set of candidates with ID `which`.

    @param which An identifier returned by "etch" or "vote."
    */
    function vote(bytes32 which) {
        var voter = _voters[msg.sender];
        subWeight(voter.weight, _slates[voter.slate]);

        voter.slate = which;
        addWeight(voter.weight, _slates[voter.slate]);
    }


    /**
    @notice Lock up `amt` wei voting tokens and increase your vote weight
    by the same amount.

    @param amt Number of tokens (in the token's smallest denomination) to lock.
    */
    function lock(uint128 amt) {
        var voter = _voters[msg.sender];
        addWeight(amt, _slates[voter.slate]);

        _voters[msg.sender].weight += amt;

        _token.transferFrom(msg.sender, this, amt);
    }


    /**
    @notice Retrieve `amt` wei of your locked voting tokens and decrease your
    vote weight by the same amount.

    @param amt Number of tokens (in the token's smallest denomination) to free.
    */
    function free(uint128 amt) {
        var voter = _voters[msg.sender];
        subWeight(amt, _slates[voter.slate]);

        voter.weight -= amt;

        _token.transfer(msg.sender, amt);
    }


    // Throws unless the array of addresses is a ordered set.
    function requireOrderedSet(address[] guys) internal {
        if( guys.length == 0 || guys.length == 1 ) {
            return;
        }
        for( var i = 0; i < guys.length - 1; i++ ) {
            // strict inequality ensures both ordering and uniqueness
            require(uint256(bytes32(guys[i])) < uint256(bytes32(guys[i+1])));
        }
    }

    // Remove weight from slate.
    function subWeight(uint weight, Slate slate) internal {
        for(var i = 0; i < slate.guys.length; i++) {
            _votes[slate.guys[i]] -= weight;
        }
    }

    // Add weight to slate.
    function addWeight(uint weight, Slate slate) internal {
        for(var i = 0; i < slate.guys.length; i++) {
            _votes[slate.guys[i]] += weight;
        }
    }
}
