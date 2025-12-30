angular.module('beamng.apps')
.directive('raceEditor', [function() {
  return {
    templateUrl: '/ui/modules/apps/RaceEditor/app.html',
    replace: true,
    restrict: 'EA',
    scope: {},
    controller: 'RaceEditorController'
  };
}])
.controller('RaceEditorController', ['$scope', '$timeout', function($scope, $timeout) {

  // ==================== STATE ====================

  $scope.editing = false;
  $scope.currentTrackId = '';
  $scope.trackList = [];
  $scope.newTrackName = '';

  // Track data
  $scope.trackData = {
    name: '',
    spawns: {
      player: null,
      adversaries: []
    },
    checkpoints: [],
    finish: null
  };

  // UI state
  $scope.showSpawns = true;
  $scope.showCheckpoints = true;
  $scope.showFinish = true;
  $scope.showSettings = false;

  // Race settings
  $scope.settings = {
    minBet: 1000,
    maxBet: 50000,
    difficulty: 2
  };

  // ==================== TRACK MANAGEMENT ====================

  $scope.loadTrackList = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.getTrackList()');
  };

  $scope.selectTrack = function(trackId) {
    if (trackId) {
      $scope.currentTrackId = trackId;
      bngApi.engineLua('extensions.carTheft_raceEditorUI.loadTrack("' + trackId + '")');
    }
  };

  $scope.createNewTrack = function() {
    var name = $scope.newTrackName || 'New Race';
    bngApi.engineLua('extensions.carTheft_raceEditorUI.createNewTrack("' + name.replace(/"/g, '\\"') + '")');
    $scope.newTrackName = '';
  };

  $scope.saveTrack = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.saveTrack()');
  };

  $scope.deleteTrack = function() {
    if (confirm('Delete track "' + $scope.trackData.name + '"?')) {
      bngApi.engineLua('extensions.carTheft_raceEditorUI.deleteTrack("' + $scope.currentTrackId + '")');
    }
  };

  $scope.updateTrackName = function() {
    var name = $scope.trackData.name || 'Unnamed';
    bngApi.engineLua('extensions.carTheft_raceEditorUI.updateTrackName("' + name.replace(/"/g, '\\"') + '")');
  };

  // ==================== SPAWN POSITIONS ====================

  $scope.setPlayerSpawn = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.setPlayerSpawn()');
  };

  $scope.clearPlayerSpawn = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.clearPlayerSpawn()');
  };

  $scope.addAdversarySpawn = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.addAdversarySpawn()');
  };

  $scope.removeAdversarySpawn = function(index) {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.removeAdversarySpawn(' + index + ')');
  };

  $scope.teleportToSpawn = function(type, index) {
    if (type === 'player') {
      bngApi.engineLua('extensions.carTheft_raceEditorUI.teleportToPlayerSpawn()');
    } else {
      bngApi.engineLua('extensions.carTheft_raceEditorUI.teleportToAdversarySpawn(' + index + ')');
    }
  };

  // ==================== CHECKPOINTS ====================

  $scope.addCheckpoint = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.addCheckpoint()');
  };

  $scope.removeCheckpoint = function(index) {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.removeCheckpoint(' + index + ')');
  };

  $scope.teleportToCheckpoint = function(index) {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.teleportToCheckpoint(' + index + ')');
  };

  $scope.setCheckpointWidth = function(index, width) {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.setCheckpointWidth(' + index + ', ' + width + ')');
  };

  // ==================== FINISH LINE ====================

  $scope.setFinishLine = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.setFinishLine()');
  };

  $scope.clearFinishLine = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.clearFinishLine()');
  };

  $scope.teleportToFinish = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.teleportToFinish()');
  };

  // ==================== SIMULATION ====================

  $scope.simulate = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.simulate()');
  };

  $scope.previewRoute = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.previewRoute()');
  };

  $scope.clearMarkers = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.clearMarkers()');
  };

  // ==================== EDITING TOGGLE ====================

  $scope.toggleEditing = function() {
    $scope.editing = !$scope.editing;
    if ($scope.editing) {
      bngApi.engineLua('extensions.load("carTheft_raceEditorUI")');
      bngApi.engineLua('extensions.carTheft_raceEditorUI.startEditing()');
      $scope.loadTrackList();
    } else {
      bngApi.engineLua('extensions.carTheft_raceEditorUI.stopEditing()');
    }
  };

  // ==================== SETTINGS ====================

  $scope.toggleSettings = function() {
    $scope.showSettings = !$scope.showSettings;
  };

  $scope.updateSettings = function() {
    bngApi.engineLua('extensions.carTheft_raceEditorUI.updateSettings({' +
      'minBet = ' + $scope.settings.minBet + ', ' +
      'maxBet = ' + $scope.settings.maxBet + ', ' +
      'difficulty = ' + $scope.settings.difficulty +
    '})');
  };

  // ==================== FORMAT HELPERS ====================

  $scope.formatPos = function(pos) {
    if (!pos) return 'Not set';
    return pos.x.toFixed(1) + ', ' + pos.y.toFixed(1) + ', ' + pos.z.toFixed(1);
  };

  $scope.formatRot = function(rot) {
    if (!rot) return '';
    // Convert quaternion to yaw angle for display
    var yaw = Math.atan2(2 * (rot.w * rot.z + rot.x * rot.y), 1 - 2 * (rot.y * rot.y + rot.z * rot.z));
    return Math.round(yaw * 180 / Math.PI) + ' deg';
  };

  // ==================== EVENT LISTENERS ====================

  $scope.$on('RaceEditorTrackList', function(event, data) {
    $scope.$evalAsync(function() {
      $scope.trackList = data || [];
    });
  });

  $scope.$on('RaceEditorTrackLoaded', function(event, data) {
    $scope.$evalAsync(function() {
      if (data) {
        $scope.currentTrackId = data.id || '';
        $scope.trackData.name = data.name || '';
        $scope.trackData.spawns = data.spawns || { player: null, adversaries: [] };
        $scope.trackData.checkpoints = data.checkpoints || [];
        $scope.trackData.finish = data.finish || null;
        $scope.settings = {
          minBet: data.minBet || 1000,
          maxBet: data.maxBet || 50000,
          difficulty: data.difficulty || 2
        };
      }
    });
  });

  $scope.$on('RaceEditorSpawnsUpdated', function(event, data) {
    $scope.$evalAsync(function() {
      if (data) {
        $scope.trackData.spawns = data;
      }
    });
  });

  $scope.$on('RaceEditorCheckpointsUpdated', function(event, data) {
    $scope.$evalAsync(function() {
      if (data) {
        $scope.trackData.checkpoints = data;
      }
    });
  });

  $scope.$on('RaceEditorFinishUpdated', function(event, data) {
    $scope.$evalAsync(function() {
      $scope.trackData.finish = data;
    });
  });

  $scope.$on('RaceEditorSaved', function(event, data) {
    $scope.$evalAsync(function() {
      if (data && data.success) {
        console.log('Race Editor: Track saved successfully');
        $scope.loadTrackList();
      }
    });
  });

  $scope.$on('RaceEditorNewTrack', function(event, data) {
    $scope.$evalAsync(function() {
      if (data) {
        $scope.currentTrackId = data.id;
        $scope.trackData = {
          name: data.name,
          spawns: { player: null, adversaries: [] },
          checkpoints: [],
          finish: null
        };
        $scope.loadTrackList();
      }
    });
  });

  $scope.$on('RaceEditorDeleted', function(event, data) {
    $scope.$evalAsync(function() {
      $scope.currentTrackId = '';
      $scope.trackData = {
        name: '',
        spawns: { player: null, adversaries: [] },
        checkpoints: [],
        finish: null
      };
      $scope.loadTrackList();
    });
  });

  $scope.$on('RaceEditorSimulating', function(event, data) {
    $scope.$evalAsync(function() {
      if (data && data.started) {
        console.log('Race Editor: Simulation started');
      }
    });
  });

  $scope.$on('RaceEditorError', function(event, data) {
    console.error('Race Editor error:', data.message);
  });

  // ==================== INITIALIZATION ====================

  // Request initial state when opening
  bngApi.engineLua('extensions.load("carTheft_raceEditorUI")');

}]);
