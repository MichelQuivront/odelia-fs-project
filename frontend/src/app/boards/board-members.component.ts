import { HttpErrorResponse } from '@angular/common/http';
import { Component, OnInit, computed, inject, input, signal } from '@angular/core';
import { FormsModule } from '@angular/forms';

import { AuthService } from '../auth/auth.service';
import { Board, BoardMember } from '../models/board';
import { BoardService } from '../services/board.service';

/**
 * Members panel of a board (F2-F4): everyone who can open the board sees the
 * members; only the owner (or an admin) gets the add / remove controls. The
 * backend enforces the same rule - hiding the controls is only a convenience.
 */
@Component({
  selector: 'app-board-members',
  imports: [FormsModule],
  templateUrl: './board-members.component.html',
  styleUrl: './board-members.component.css'
})
export class BoardMembersComponent implements OnInit {
  private readonly boardService = inject(BoardService);
  private readonly auth = inject(AuthService);

  readonly board = input.required<Board>();

  readonly members = signal<BoardMember[]>([]);
  readonly loading = signal(false);
  readonly error = signal<string | null>(null);

  /** Owner or admin: may manage the membership. */
  readonly canManage = computed(
    () => this.auth.isAdmin() || this.board().owner === this.auth.username()
  );

  newUsername = '';

  ngOnInit(): void {
    this.reload();
  }

  reload(): void {
    const boardId = this.board().id;
    if (boardId === undefined) {
      return;
    }
    this.loading.set(true);
    this.error.set(null);
    this.boardService.getMembers(boardId).subscribe({
      next: members => {
        this.members.set(members);
        this.loading.set(false);
      },
      error: err => this.fail('Could not load the members', err)
    });
  }

  addMember(): void {
    const boardId = this.board().id;
    const username = this.newUsername.trim();
    if (boardId === undefined || !username) {
      return;
    }
    this.error.set(null);
    this.boardService.addMember(boardId, username).subscribe({
      next: member => {
        this.members.update(members =>
          [...members, member].sort((a, b) => a.username.localeCompare(b.username))
        );
        this.newUsername = '';
      },
      error: err => this.fail(`Could not add "${username}"`, err)
    });
  }

  removeMember(member: BoardMember): void {
    const boardId = this.board().id;
    if (boardId === undefined) {
      return;
    }
    if (!confirm(`Remove "${member.username}" from this board?`)) {
      return;
    }
    this.error.set(null);
    this.boardService.removeMember(boardId, member.username).subscribe({
      next: () => this.members.update(members => members.filter(m => m.username !== member.username)),
      error: err => this.fail(`Could not remove "${member.username}"`, err)
    });
  }

  private fail(message: string, err: unknown): void {
    console.error(message, err);
    const reason = this.reason(err);
    this.error.set(reason ? `${message}: ${reason}` : message);
    this.loading.set(false);
  }

  /** A readable explanation of the status codes the membership endpoints return. */
  private reason(err: unknown): string | null {
    if (!(err instanceof HttpErrorResponse)) {
      return null;
    }
    const serverMessage = typeof err.error?.error === 'string' ? err.error.error : null;
    switch (err.status) {
      case 400:
        return serverMessage ?? 'already a member, or the owner of the board';
      case 403:
        return 'only the board owner can manage its members';
      case 404:
        return serverMessage ?? 'not found';
      default:
        return null;
    }
  }
}
