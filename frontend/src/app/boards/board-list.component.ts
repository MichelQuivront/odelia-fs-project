import { Component, ElementRef, OnInit, inject, signal, viewChild } from '@angular/core';
import { DatePipe } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';

import { Board } from '../models/board';
import { BoardService } from '../services/board.service';

/**
 * Lists the boards, creates one, renames one inline, deletes one. Each board
 * name links to the drag-and-drop board detail view ({@code /boards/:id}).
 */
@Component({
  selector: 'app-board-list',
  imports: [FormsModule, DatePipe, RouterLink],
  templateUrl: './board-list.component.html',
  styleUrl: './board-list.component.css'
})
export class BoardListComponent implements OnInit {
  private readonly boardService = inject(BoardService);

  readonly boards = signal<Board[]>([]);
  readonly loading = signal(false);
  readonly error = signal<string | null>(null);

  newBoardName = '';

  /** Id of the board whose name is being edited, or null when no editor is open. */
  readonly editingBoardId = signal<number | null>(null);
  /** True while the PUT is in flight, so Save cannot be sent twice. */
  readonly renaming = signal(false);
  /**
   * Working copy bound to the rename input. Never bound to `board.name`
   * directly, so Cancel leaves the displayed board untouched.
   */
  renameDraft = '';

  /** The rename input (only one is in the DOM at a time), focused when the editor opens. */
  private readonly renameInput = viewChild<ElementRef<HTMLInputElement>>('renameInput');

  ngOnInit(): void {
    this.reload();
  }

  reload(): void {
    this.loading.set(true);
    this.error.set(null);
    this.boardService.getBoards().subscribe({
      next: boards => {
        this.boards.set(boards);
        this.loading.set(false);
      },
      error: err => this.fail('Could not load the boards', err)
    });
  }

  createBoard(): void {
    const name = this.newBoardName.trim();
    if (!name) {
      return;
    }
    this.error.set(null);
    this.boardService.createBoard(name).subscribe({
      next: board => {
        this.boards.update(boards => [...boards, board].sort(byName));
        this.newBoardName = '';
      },
      error: err => this.fail(`Could not create the board "${name}"`, err)
    });
  }

  /** Opens the inline editor for one board; any other open editor is closed. */
  startRename(board: Board): void {
    if (board.id === undefined) {
      return;
    }
    this.editingBoardId.set(board.id);
    this.renameDraft = board.name;
    setTimeout(() => this.renameInput()?.nativeElement.select());
  }

  cancelRename(): void {
    this.editingBoardId.set(null);
    this.renameDraft = '';
  }

  /** Sends one `PUT /api/boards/{id}` and swaps the returned board into the sorted list. */
  saveRename(board: Board): void {
    const name = this.renameDraft.trim();
    if (!name || board.id === undefined || this.renaming()) {
      return;
    }
    this.error.set(null);
    this.renaming.set(true);
    this.boardService.renameBoard(board.id, name).subscribe({
      next: updated => {
        this.boards.update(boards => boards.map(b => (b.id === board.id ? updated : b)).sort(byName));
        this.renaming.set(false);
        this.cancelRename();
      },
      error: err => {
        // Keep the editor open with the draft, so the user can retry or cancel.
        this.renaming.set(false);
        this.fail(`Could not rename "${board.name}"`, err);
      }
    });
  }

  deleteBoard(board: Board): void {
    if (board.id === undefined) {
      return;
    }
    if (!confirm(`Delete board "${board.name}"? This cannot be undone.`)) {
      return;
    }
    this.error.set(null);
    this.boardService.deleteBoard(board.id).subscribe({
      next: () => this.boards.update(boards => boards.filter(b => b.id !== board.id)),
      error: err => this.fail(`Could not delete the board "${board.name}"`, err)
    });
  }

  private fail(message: string, err: unknown): void {
    console.error(message, err);
    this.error.set(message);
    this.loading.set(false);
  }
}

/** The list is always kept sorted by name, as `GET /api/boards` returns it. */
function byName(a: Board, b: Board): number {
  return a.name.localeCompare(b.name);
}
